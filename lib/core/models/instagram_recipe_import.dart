import 'dart:math';

import 'package:plateplan/core/measurement/ingredient_display_units.dart';
import 'package:plateplan/core/models/app_models.dart';
import 'package:plateplan/core/recipes/ingredient_line_parser.dart';
import 'package:plateplan/core/strings/ingredient_amount_display.dart';

/// Removes Instagram / reel / ig.me URL tokens line-by-line. Preserves newlines
/// so the first non-empty line stays the natural recipe title.
///
/// **Important:** A naive `https?://[^\s]+` removes the entire whitespace token. Shares
/// often fuse caption text to the URL with **no space** (e.g. `.../reel/AbCdEfGhIjKSalmon`).
/// We strip Instagram paths with a **bounded** media id first, then other https links.
String stripInstagramUrlsForCaption(String input) {
  // Instagram media shortcodes are 11 chars (base64url). Stopping here preserves fused caption.
  // Optional slash after shortcode so we do not leave a lone "/" on the line before the caption.
  final igReelPostTv = RegExp(
    r'https?://(?:www\.)?(?:m\.)?instagram\.com/(?:reel|reels|p|tv)/[A-Za-z0-9_-]{11}(?:/(?:\?[^\s]*)?|\?[^\s]*)?',
    caseSensitive: false,
  );
  // Older or test URLs may use shorter post ids; lookahead ensures we do not eat fused caption
  // (next char after the id must be /, ?, whitespace, or end — not a continuation of the dish name).
  // Do NOT use $ in the lookahead: at end-of-line, greedy {3,20} can absorb a fused caption
  // (letters after the real shortcode) and then $ matches, wiping the whole line → false "URL only".
  final igReelPostTvLoose = RegExp(
    r'https?://(?:www\.)?(?:m\.)?instagram\.com/(?:reel|reels|p|tv)/[A-Za-z0-9_-]{3,20}(?=/|\?|\s)',
    caseSensitive: false,
  );
  // Stories: /stories/<user>/<id>/...
  final igStories = RegExp(
    r'https?://(?:www\.)?(?:m\.)?instagram\.com/stories/[^/\s]+/[^/\s]+(?:/[^\s]*)?/?(?:\?[^\s]*)?',
    caseSensitive: false,
  );
  final igShort = RegExp(
    r'https?://(?:www\.)?ig\.me/[^\s]+',
    caseSensitive: false,
  );
  final lInstagram = RegExp(
    r'https?://l\.instagram\.com/[^\s]+',
    caseSensitive: false,
  );
  // Do not match instagram.com / ig.me — a failed narrow reel match must not fall through
  // to stripping the whole https token (that would swallow caption fused without a space).
  final genericHttps = RegExp(
    r'https?://(?!www\.instagram\.com|m\.instagram\.com|instagram\.com|l\.instagram\.com|ig\.me)[^\s]+',
    caseSensitive: false,
  );
  // Shares that omit "https://" — same bounded path as [igReelPostTv], not [^\s]+.
  final bareIgReelPostTv = RegExp(
    r'(?:www\.)?(?:m\.)?instagram\.com/(?:reel|reels|p|tv)/[A-Za-z0-9_-]{11}(?:/(?:\?[^\s]*)?|\?[^\s]*)?',
    caseSensitive: false,
  );
  final bareIgReelPostTvLoose = RegExp(
    r'(?:www\.)?(?:m\.)?instagram\.com/(?:reel|reels|p|tv)/[A-Za-z0-9_-]{3,20}(?=/|\?|\s)',
    caseSensitive: false,
  );
  final bareIgStories = RegExp(
    r'(?:www\.)?(?:m\.)?instagram\.com/stories/[^/\s]+/[^/\s]+(?:\?[^\s]*)?',
    caseSensitive: false,
  );
  final bareIgMe = RegExp(
    r'(?:www\.)?ig\.me/[^\s]+',
    caseSensitive: false,
  );

  String stripLine(String line) {
    var s = line.replaceAll(igReelPostTv, ' ');
    s = s.replaceAll(igReelPostTvLoose, ' ');
    s = s.replaceAll(igStories, ' ');
    s = s.replaceAll(igShort, ' ');
    s = s.replaceAll(lInstagram, ' ');
    s = s.replaceAll(genericHttps, ' ');
    s = s.replaceAll(bareIgReelPostTv, ' ');
    s = s.replaceAll(bareIgReelPostTvLoose, ' ');
    s = s.replaceAll(bareIgStories, ' ');
    s = s.replaceAll(bareIgMe, ' ');
    return s.replaceAll(RegExp(r' +'), ' ').trim();
  }

  return input
      .split(RegExp(r'\r?\n'))
      .map(stripLine)
      .where((line) => line.isNotEmpty)
      .join('\n')
      .trim();
}

/// Text sent to Gemini after URL stripping.
///
/// If stripping removes everything (URL-only share, short `ig.me` links, or regex edge cases),
/// we still pass the **full raw** trimmed share so the model always receives what the OS gave
/// us. The previous heuristic could return `''` for short Instagram links (no digits / low
/// letter count), which incorrectly triggered "URL alone" even though Gemini had been called.
String captionForInstagramGemini(String sharedContent) {
  final raw = sharedContent.trim();
  if (raw.isEmpty) return '';
  final stripped = stripInstagramUrlsForCaption(sharedContent).trim();
  if (stripped.isNotEmpty) return stripped;
  return raw;
}

/// Maps Gemini / Instagram labels like "dinner" to [MealType] without using [_mealTypeFromDb].
MealType mealTypeFromInstagramLabel(String? raw) {
  final s = (raw ?? '').trim().toLowerCase();
  const mains = <String>{
    'breakfast',
    'brunch',
    'lunch',
    'dinner',
    'supper',
    'entree',
    'main',
    'main course',
  };
  const sides = <String>{'side', 'side dish', 'salad'};
  const sauces = <String>{'sauce', 'condiment'};
  const snacks = <String>{'snack', 'appetizer', 'starter'};
  const desserts = <String>{'dessert', 'sweet'};
  if (mains.contains(s)) return MealType.entree;
  if (sides.contains(s)) return MealType.side;
  if (sauces.contains(s)) return MealType.sauce;
  if (snacks.contains(s)) return MealType.snack;
  if (desserts.contains(s)) return MealType.dessert;
  return MealType.entree;
}

Ingredient _ingredientFromInstagramJson(Map<String, dynamic> json) {
  final name = json['name']?.toString().trim() ?? '';
  final amountRaw = json['amount'];
  final unitRaw = json['unit']?.toString().trim() ?? '';

  if (amountRaw is num) {
    return Ingredient(
      name: name,
      amount: amountRaw.toDouble(),
      unit: unitRaw,
      category: GroceryCategory.other,
    );
  }

  final str = amountRaw?.toString().trim() ?? '';
  if (str.isEmpty && unitRaw.isEmpty) {
    return Ingredient(
      name: name,
      amount: 0,
      unit: '',
      category: GroceryCategory.other,
      qualitative: false,
    );
  }

  if (str.isEmpty) {
    return Ingredient(
      name: name,
      amount: 0,
      unit: unitRaw,
      category: GroceryCategory.other,
      qualitative: true,
    );
  }

  final leading = RegExp(r'^([\d\s.,/\-–—½¼¾⅓⅔⅛⅜⅝⅞]+)\s*(.*)$')
      .firstMatch(str);
  if (leading != null) {
    final numPart = leading.group(1)!;
    final restFromAmount = leading.group(2)?.trim() ?? '';
    final parsed = _parseAmountToken(numPart);
    if (parsed != null) {
      final unitCombined = [unitRaw, restFromAmount]
          .where((e) => e.isNotEmpty)
          .join(' ')
          .trim();
      return Ingredient(
        name: name,
        amount: parsed,
        unit: unitCombined,
        category: GroceryCategory.other,
      );
    }
  }

  return Ingredient(
    name: name,
    amount: 0,
    unit: [str, unitRaw].where((e) => e.isNotEmpty).join(' ').trim(),
    category: GroceryCategory.other,
    qualitative: true,
  );
}

Ingredient _ingredientWith(
  Ingredient base, {
  required String name,
  required double amount,
  required String unit,
  required bool qualitative,
}) {
  return Ingredient(
    name: name,
    amount: amount,
    unit: unit,
    category: base.category,
    qualitative: qualitative,
    fdcId: base.fdcId,
    fdcDescription: base.fdcDescription,
    lineNutrition: base.lineNutrition,
    fdcNutritionEstimated: base.fdcNutritionEstimated,
    fdcTypicalAverage: base.fdcTypicalAverage,
  );
}

/// Normalizes Gemini/book-scan [Ingredient] rows to canonical unit keys and
/// recovers amount/unit/name splits when the model merged fields.
Ingredient normalizeImportedIngredient(Ingredient i) {
  if (i.qualitative) {
    final combined = [i.unit, i.name]
        .map((s) => s.trim())
        .where((s) => s.isNotEmpty)
        .join(' ');
    final parsed = tryParseMeasuredIngredientLine(combined);
    if (parsed != null) {
      final u = normalizeIngredientUnitKey(parsed.unit) ?? parsed.unit;
      return _ingredientWith(
        i,
        name: parsed.name,
        amount: parsed.amount,
        unit: u,
        qualitative: false,
      );
    }
    return i;
  }

  var name = i.name.trim();
  var amount = i.amount;
  var unit = i.unit.trim();

  // Model puts the whole line in [name] (e.g. "Vinegar 2 Tbsp.") with empty amount/unit.
  if (amount <= 0 && unit.isEmpty && name.isNotEmpty) {
    final leading = tryParseMeasuredIngredientLine(name);
    if (leading != null) {
      final u = normalizeIngredientUnitKey(leading.unit) ?? leading.unit;
      return _ingredientWith(
        i,
        name: leading.name,
        amount: leading.amount,
        unit: u,
        qualitative: false,
      );
    }
    final trailing = RegExp(
      r'^(.+?)\s+([\d\s.,/\-–—½¼¾⅓⅔⅛⅜⅝⅞]+)\s+(.+)$',
    ).firstMatch(name);
    if (trailing != null) {
      final namePart = trailing.group(1)!.trim();
      final amountPart = trailing.group(2)!.trim();
      final unitPart = trailing.group(3)!.trim();
      final amt = _parseAmountToken(amountPart);
      final u = normalizeIngredientUnitKey(unitPart);
      if (amt != null && amt > 0 && u != null && namePart.isNotEmpty) {
        return _ingredientWith(
          i,
          name: namePart,
          amount: amt,
          unit: u,
          qualitative: false,
        );
      }
    }
  }

  if (name.isEmpty && amount <= 0 && unit.isEmpty) {
    return i;
  }

  final direct = normalizeIngredientUnitKey(unit);
  if (direct != null) {
    return _ingredientWith(i, name: name, amount: amount, unit: direct, qualitative: false);
  }

  final unitParts =
      unit.split(RegExp(r'\s+')).where((s) => s.isNotEmpty).toList();
  if (unitParts.length > 1) {
    final firstKey = normalizeIngredientUnitKey(unitParts.first);
    if (firstKey != null) {
      final rest = unitParts.skip(1).join(' ');
      final newName =
          rest.isEmpty ? name : (name.isEmpty ? rest : '$rest $name').trim();
      return _ingredientWith(
        i,
        name: newName,
        amount: amount,
        unit: firstKey,
        qualitative: false,
      );
    }
  }

  if (amount > 0 && name.isNotEmpty) {
    final line = '${formatIngredientAmount(amount)} $unit $name'.trim();
    final parsed = tryParseMeasuredIngredientLine(line);
    if (parsed != null) {
      final u = normalizeIngredientUnitKey(parsed.unit) ?? parsed.unit;
      return _ingredientWith(
        i,
        name: parsed.name,
        amount: parsed.amount,
        unit: u,
        qualitative: false,
      );
    }
  }

  return i;
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

  // Handle ranges (e.g. "1-2", "1 1/2-2").
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

  // Mixed number: "1 1/2"
  final mixed = RegExp(r'^(\d+)\s+(\d+)\s*/\s*(\d+)$').firstMatch(t);
  if (mixed != null) {
    final whole = double.tryParse(mixed.group(1)!);
    final a = double.tryParse(mixed.group(2)!);
    final b = double.tryParse(mixed.group(3)!);
    if (whole != null && a != null && b != null && b != 0) {
      return whole + (a / b);
    }
  }

  // Fraction: "1/2"
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

/// Max length for a caption line we treat as a recipe title (longer lines look like paragraphs).
const int kInstagramInferredTitleMaxLength = 120;

final RegExp _urlToken = RegExp(r'^https?://\S+$', caseSensitive: false);

bool _isUrlOnlyLine(String line) {
  final t = line.trim();
  if (t.isEmpty) return true;
  for (final tok in t.split(RegExp(r'\s+'))) {
    if (!_urlToken.hasMatch(tok)) return false;
  }
  return true;
}

bool _isIngredientsSectionHeader(String line) {
  return RegExp(r'^\s*ingredients?\s*:?\s*$', caseSensitive: false)
      .hasMatch(line);
}

bool _isSectionHeaderLine(String line) {
  return RegExp(
    r'^\s*(ingredients?|instructions?|method|directions|steps|prep|cook\s*time|notes|tips)\s*:?\s*$',
    caseSensitive: false,
  ).hasMatch(line);
}

bool _isHashtagOnlyLine(String line) {
  final t = line.trim();
  if (t.isEmpty) return true;
  for (final tok in t.split(RegExp(r'\s+'))) {
    if (RegExp(r'^#\w').hasMatch(tok)) continue;
    if (RegExp(r'[a-zA-Z]').hasMatch(tok)) return false;
  }
  return true;
}

/// Line starts like a quantity + common cooking unit (not a dish name like "1-Pot Pasta").
final RegExp _ingredientLineLead = RegExp(
  r'^\s*([\d\s.,/\-–—½¼¾⅓⅔⅛⅜⅝⅞]+)\s+'
  r'(cups?|tbsp|tsp|oz|ounce|ounces|g|kg|grams?|ml|l|lb|lbs|tablespoons?|teaspoons?|pinch|cloves?|eggs?|large|medium|small|stalks?|sticks?|slices?|packets?|cans?|bunch|bunches)\b',
  caseSensitive: false,
);

bool _looksLikeIngredientLine(String line) {
  return _ingredientLineLead.hasMatch(line);
}

String _normalizeInstagramTitle(String line) {
  var s = line.replaceAll(RegExp(r'\s+'), ' ').trim();
  s = s.replaceAll(RegExp(r'(\s+#\w+)+$'), '');
  return s.trim();
}

String? _tryLineAsInstagramTitle(String lineTrim) {
  if (_isIngredientsSectionHeader(lineTrim)) return null;
  if (lineTrim.length > kInstagramInferredTitleMaxLength) return null;
  if (_isSectionHeaderLine(lineTrim)) return null;
  if (_looksLikeIngredientLine(lineTrim)) return null;
  final normalized = _normalizeInstagramTitle(lineTrim);
  if (normalized.isEmpty) return null;
  if (normalized.length > kInstagramInferredTitleMaxLength) return null;
  return normalized;
}

/// Subtitle lines like "For the Fish Bites" — not the recipe headline.
bool _isSubtitleForTheLine(String line) {
  return RegExp(r'^\s*For the\s', caseSensitive: false).hasMatch(line);
}

String _truncateAtWordBoundary(String s, int maxLen) {
  if (s.length <= maxLen) return s;
  var t = s.substring(0, maxLen);
  final lastSpace = t.lastIndexOf(' ');
  if (lastSpace > maxLen ~/ 3) return t.substring(0, lastSpace).trim();
  return t.trim();
}

/// Fallback: scan every line (used when headline block is empty or yields no title).
String? _inferTitleFromLineScan(String raw) {
  final lines = raw.split(RegExp(r'\r?\n')).map((e) => e.trim()).toList();
  for (final lineTrim in lines) {
    if (lineTrim.isEmpty) continue;
    if (_isUrlOnlyLine(lineTrim)) continue;
    if (_isHashtagOnlyLine(lineTrim)) continue;
    final title = _tryLineAsInstagramTitle(lineTrim);
    if (title != null) return title;
  }
  return null;
}

/// Picks a title from shared Instagram text (URL + caption) when the caption has a clear headline.
///
/// Prefer text **before the first "Ingredients:"** so one long caption line or a wall of text
/// still yields the dish name instead of failing length checks and falling back to Gemini's title.
/// Skips hashtag-only lines, [For the …] subtitles, then each remaining line
/// until one looks like a title.
///
/// Uses [stripInstagramUrlsForCaption] first (not only "URL-only" lines), so a single share line
/// like `https://…/reel/XXXXXXXXXXX Bok Choy stir-fry` still yields **Bok Choy stir-fry** instead of
/// failing inference and falling back to a hallucinated model title.
String? inferInstagramRecipeTitle(String sharedContent) {
  final raw = sharedContent.trim();
  if (raw.isEmpty) return null;

  final withoutUrls = stripInstagramUrlsForCaption(raw);
  if (withoutUrls.isEmpty) return null;

  final firstIngredients = RegExp(
    r'\bIngredients\s*:\s*',
    caseSensitive: false,
  ).firstMatch(withoutUrls);
  final headBeforeIngredients = firstIngredients != null
      ? withoutUrls.substring(0, firstIngredients.start).trim()
      : withoutUrls;

  if (headBeforeIngredients.isNotEmpty) {
    final candidateLines = headBeforeIngredients
        .split(RegExp(r'\r?\n'))
        .map((e) => e.trim())
        .where((e) => e.isNotEmpty)
        .toList();
    for (final line in candidateLines) {
      if (_isHashtagOnlyLine(line)) continue;
      if (_isSubtitleForTheLine(line)) continue;
      var candidate = line;
      if (candidate.length > kInstagramInferredTitleMaxLength) {
        candidate =
            _truncateAtWordBoundary(candidate, kInstagramInferredTitleMaxLength);
      }
      final title = _tryLineAsInstagramTitle(candidate);
      if (title != null) return title;
    }
  }

  return _inferTitleFromLineScan(withoutUrls);
}

/// True when the model title plausibly came from the caption (substring or word overlap).
bool _geminiTitleSupportedByCaption(String geminiTitle, String captionStripped) {
  final g = geminiTitle.toLowerCase().trim();
  final c = captionStripped.toLowerCase();
  if (g.isEmpty) return false;
  if (c.contains(g)) return true;
  final words =
      g.split(RegExp(r'\s+')).where((w) => w.length > 2).toList();
  if (words.isEmpty) return true;
  final hits = words.where((w) => c.contains(w)).length;
  return hits >= (words.length / 2).ceil();
}

/// Last-resort title: first usable line of stripped caption (when inference returned null).
String? _firstCaptionLineAsTitleFallback(String stripped) {
  for (final line
      in stripped.split(RegExp(r'\r?\n')).map((e) => e.trim())) {
    if (line.isEmpty) continue;
    if (_isHashtagOnlyLine(line)) continue;
    if (_isSubtitleForTheLine(line)) continue;
    if (_isIngredientsSectionHeader(line)) continue;
    if (_isSectionHeaderLine(line)) continue;
    if (_looksLikeIngredientLine(line)) continue;
    final t = _normalizeInstagramTitle(line);
    if (t.isEmpty) continue;
    if (t.length > kInstagramInferredTitleMaxLength) {
      return _truncateAtWordBoundary(t, kInstagramInferredTitleMaxLength);
    }
    return t;
  }
  return null;
}

String _pickInstagramRecipeTitle({
  required String? inferredTitle,
  required String? geminiTitle,
  required String captionStripped,
}) {
  final inf = inferredTitle?.trim();
  if (inf != null && inf.isNotEmpty) return inf;

  final g = geminiTitle?.trim() ?? '';
  if (captionStripped.trim().isEmpty) {
    return g.isNotEmpty ? g : 'Imported recipe';
  }

  if (g.isNotEmpty && _geminiTitleSupportedByCaption(g, captionStripped)) {
    return g;
  }

  final fallback = _firstCaptionLineAsTitleFallback(captionStripped);
  if (fallback != null && fallback.isNotEmpty) return fallback;

  if (g.isNotEmpty) return g;
  return 'Imported recipe';
}

/// Noodle/pasta tokens models sometimes hallucinate when the caption is fish/meat-only.
bool _ingredientLooksLikeHallucinatedCarbNotInCaption(
  Ingredient i,
  String captionLower,
) {
  const tokens = <String>[
    'pasta',
    'spaghetti',
    'linguine',
    'fettuccine',
    'penne',
    'rigatoni',
    'noodles',
    'orzo',
    'gnocchi',
    'macaroni',
    'fusilli',
    'cavatelli',
  ];
  final name = i.name.toLowerCase();
  for (final t in tokens) {
    if (name.contains(t) && !captionLower.contains(t)) return true;
  }
  return false;
}

/// Builds a [Recipe] from Gemini JSON for Instagram or book-scan import (see [GeminiService]).
Recipe recipeFromInstagramGeminiMap(
  Map<String, dynamic> json, {
  String? id,
  String? imageUrl,
  String? sourceUrl,
  String? sharedContent,
  String source = 'instagram_import',
}) {
  final tempId =
      id ?? 'import-${DateTime.now().millisecondsSinceEpoch}-${Random().nextInt(999999)}';
  var ingredients = (json['ingredients'] as List?)
          ?.whereType<Map>()
          .map((e) => _ingredientFromInstagramJson(Map<String, dynamic>.from(e)))
          .map(normalizeImportedIngredient)
          .where((i) => i.name.isNotEmpty)
          .toList() ??
      const <Ingredient>[];
  if (source == 'instagram_import' &&
      sharedContent != null &&
      sharedContent.trim().isNotEmpty) {
    final cap = sharedContent.toLowerCase();
    ingredients = ingredients
        .where(
          (i) => !_ingredientLooksLikeHallucinatedCarbNotInCaption(i, cap),
        )
        .toList();
  }

  final instructions = (json['instructions'] as List?)
          ?.map((e) => e.toString().trim())
          .where((s) => s.isNotEmpty)
          .toList() ??
      const <String>[];

  final servings = (json['servings'] as num?)?.toInt().clamp(1, 99) ?? 2;

  final geminiTitle = json['title']?.toString().trim();
  final inferredTitle =
      sharedContent != null ? inferInstagramRecipeTitle(sharedContent) : null;
  final captionStripped = sharedContent != null
      ? stripInstagramUrlsForCaption(sharedContent)
      : '';
  final title = _pickInstagramRecipeTitle(
    inferredTitle: inferredTitle,
    geminiTitle: geminiTitle,
    captionStripped: captionStripped,
  );

  return Recipe(
    id: tempId,
    title: title,
    description: json['description']?.toString().trim(),
    servings: servings,
    prepTime: (json['prep_time'] as num?)?.toInt(),
    cookTime: (json['cook_time'] as num?)?.toInt(),
    mealType: mealTypeFromInstagramLabel(json['meal_type']?.toString()),
    cuisineTags: (json['cuisine_tags'] as List?)
            ?.map((e) => e.toString().trim())
            .where((s) => s.isNotEmpty)
            .toList() ??
        const [],
    ingredients: ingredients,
    instructions: instructions,
    imageUrl: imageUrl,
    nutrition: const Nutrition(),
    isFavorite: false,
    isToTry: false,
    source: source,
    sourceUrl: sourceUrl,
    visibility: RecipeVisibility.personal,
  );
}
