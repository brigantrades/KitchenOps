import 'package:plateplan/core/config/env.dart';
import 'package:plateplan/core/models/app_models.dart';
import 'package:plateplan/core/network/http_client.dart';
import 'package:plateplan/core/services/fdc_nutrition_scaling.dart';

/// USDA FoodData Central search hit (minimal fields for UI).
class FdcSearchFood {
  const FdcSearchFood({
    required this.fdcId,
    required this.description,
    this.brandOwner,
    this.dataType,
    this.score,
  });

  final int fdcId;
  final String description;
  final String? brandOwner;
  final String? dataType;

  /// Search relevance when provided by FDC.
  final double? score;

  factory FdcSearchFood.fromJson(Map<String, dynamic> json) {
    return FdcSearchFood(
      fdcId: (json['fdcId'] as num?)?.toInt() ?? 0,
      description: json['description']?.toString() ?? '',
      brandOwner: json['brandOwner']?.toString(),
      dataType: json['dataType']?.toString(),
      score: (json['score'] as num?)?.toDouble(),
    );
  }
}

/// Substrings that flag SR Legacy / noisy rows that look like chain retail foods.
/// (FDC still returns some branded phrasing outside the Branded dataset.)
const _kChainRetailNoise = <String>[
  'chick-fil',
  'chick-fil-a',
  'chick fil a',
  'chickfil',
  'chick-n-',
  'smart soup',
  'mcdonald',
  'burger king',
  'taco bell',
  'wendy\'s',
  'wendys,',
  'wendys ',
  ' kfc',
  'kfc,',
  'subway',
  'starbucks',
  'dunkin',
  'domino\'s',
  'pizza hut',
  'little caesars',
  'panera',
  'chipotle',
  'jack in the box',
  'sonic drive',
  'arby\'s',
  'arbys',
  'popeyes',
  'whataburger',
  'five guys',
  'raising cane',
  'in-n-out',
  ' culver',
  ' bojangle',
  'zaxby',
  'qdoba',
  'del taco',
  'carl\'s jr',
  'hardee\'s',
  'checkers',
  'rally\'s',
  'white castle',
];

bool _isLikelyGenericIngredient(FdcSearchFood f) {
  final d = f.description.toLowerCase();
  for (final needle in _kChainRetailNoise) {
    if (d.contains(needle)) return false;
  }
  return true;
}

int _dataTypeSortKey(String? t) {
  return switch (t) {
    'Foundation' => 0,
    'Survey (FNDDS)' => 1,
    'SR Legacy' => 2,
    _ => 3,
  };
}

/// Higher = better match for recipe ingredients (raw cuts, simple meats).
/// [userQuery] avoids ranking chickpea and similar above poultry when typing
/// "chicke", "chicken", etc.
int _ingredientFitScore(
  String description,
  String? dataType,
  String userQuery,
) {
  var s = 0;
  final d = description.toLowerCase();
  final q = userQuery.trim().toLowerCase();

  if (dataType == 'Foundation') s += 8;

  final userWantsChickpea = q.contains('chickpea') ||
      q.contains('chick pea') ||
      q.contains('garbanzo');

  // Legumes: partial "chic…" matches chickpea before "chicken"; down-rank unless
  // the user query is clearly about chickpeas.
  final chickpeaInDesc = d.contains('chickpea') ||
      d.contains('chick pea') ||
      d.contains('chick peas');
  if (chickpeaInDesc && !userWantsChickpea) {
    s -= 150;
  }

  // Typing "chicke"/"chicken" — prefer real poultry wording.
  if (q.length >= 4 && q.startsWith('chick') && !userWantsChickpea) {
    if (RegExp(r'\bchicken\b').hasMatch(d)) {
      s += 60;
    }
  }

  if (d.contains(', raw') || d.endsWith(' raw') || d.contains(', raw ')) {
    s += 85;
  }
  if (d.contains('uncooked')) s += 35;
  if (d.contains('boneless')) s += 14;
  if (d.contains('skinless')) s += 14;
  if (d.contains('meat only')) s += 18;
  if (d.contains('skin not eaten')) s += 10;
  if (d.contains('whole chicken') || d.contains('chicken, whole')) s += 22;
  if (d.contains('ground chicken') || d.contains('chicken, ground')) s += 38;
  if (d.contains('ground') && d.contains('chicken')) s += 28;

  for (final cut in <String>[
    'breast',
    'thigh',
    'drumstick',
    'wing',
    'tenderloin',
    'giblet',
    'leg quarter',
  ]) {
    if (d.contains(cut)) s += 12;
  }

  const dishPenalties = <String, int>{
    'biryani': 85,
    'orange chicken': 95,
    'teriyaki': 55,
    'sweet and sour': 55,
    ' curry': 50,
    'curry,': 50,
    'stew,': 48,
    ' stew': 48,
    'soup,': 42,
    ' soup': 42,
    'casserole': 52,
    ' nugget': 55,
    'nugget,': 55,
    ' patty': 50,
    'sandwich': 52,
    ' burrito': 52,
    ' taco': 48,
    ' breaded': 28,
    ' fried': 22,
    'microwave': 35,
    'frozen dinner': 45,
    ' entree': 40,
    ' entrée': 40,
    'salad,': 35,
    ' salad': 35,
    ' pizza': 40,
    'lasagna': 40,
    'enchilada': 45,
    'quesadilla': 45,
    'pad thai': 50,
    ' lo mein': 50,
    ' fried rice': 48,
    ' dumpling': 45,
    'egg roll': 42,
    ' taquito': 45,
  };

  for (final e in dishPenalties.entries) {
    if (d.contains(e.key)) s -= e.value;
  }

  if (d.contains(' roll') || d.contains('roll,')) s -= 42;

  if (d.contains(' with ')) {
    final allowWith = d.contains('with skin') ||
        d.contains('with bone') ||
        d.contains('with meat') ||
        d.contains('with broth') ||
        d.contains('with water');
    if (!allowWith) s -= 28;
  }

  if (d.contains('sauce') && !d.contains('without sauce')) s -= 18;

  if (d.contains('grilled') || d.contains('roasted')) s -= 8;

  return s;
}

int _compareSearchResultsForQuery(
  FdcSearchFood a,
  FdcSearchFood b,
  String userQuery,
) {
  final fa = _ingredientFitScore(a.description, a.dataType, userQuery);
  final fb = _ingredientFitScore(b.description, b.dataType, userQuery);
  final fit = -fa.compareTo(fb);
  if (fit != 0) return fit;

  final dt =
      _dataTypeSortKey(a.dataType).compareTo(_dataTypeSortKey(b.dataType));
  if (dt != 0) return dt;

  final sa = a.score ?? 0;
  final sb = b.score ?? 0;
  return -sa.compareTo(sb);
}

/// Client for https://api.nal.usda.gov/fdc/v1 (USDA FoodData Central).
class FoodDataCentralService {
  FoodDataCentralService(this._client);

  final HttpClient _client;

  static Uri _apiRoot(String path, [Map<String, String>? query]) {
    return Uri.https('api.nal.usda.gov', '/fdc/v1$path', query);
  }

  /// Searches **generic** foods (Foundation, SR Legacy, FNDDS) — excludes the
  /// [Branded] dataset so short queries (e.g. "chick") are not dominated by
  /// UPC packaged / chain items. Results are filtered and ranked for cooking.
  Future<List<FdcSearchFood>> searchFoods(
    String query, {
    int pageSize = 25,
  }) async {
    final qTrim = query.trim();
    if (!Env.hasFdc || qTrim.isEmpty) return [];
    final uri = _apiRoot('/foods/search', {'api_key': Env.fdcApiKey});
    final fetchSize = (pageSize * 2).clamp(35, 50);
    final body = <String, dynamic>{
      'query': qTrim,
      'pageSize': fetchSize,
      // Omit Branded — reduces Chick-Fil-A-style hits on partial words.
      'dataType': <String>[
        'Foundation',
        'SR Legacy',
        'Survey (FNDDS)',
      ],
    };
    final json = await _client.postJson(uri, body);
    final foods = json['foods'] as List<dynamic>? ?? const [];
    final allParsed = foods
        .whereType<Map<String, dynamic>>()
        .map(FdcSearchFood.fromJson)
        .where((e) => e.fdcId > 0 && e.description.isNotEmpty)
        .toList()
      ..sort((a, b) => _compareSearchResultsForQuery(a, b, qTrim));
    final preferred =
        allParsed.where(_isLikelyGenericIngredient).toList();
    // If a short query only hits SR Legacy chain phrasing, still show rows
    // rather than nothing — generic matches stay first.
    final merged = [
      ...preferred,
      ...allParsed.where((f) => !_isLikelyGenericIngredient(f)),
    ];
    final seen = <int>{};
    final deduped = <FdcSearchFood>[];
    for (final f in merged) {
      if (seen.add(f.fdcId)) deduped.add(f);
    }
    if (deduped.length <= pageSize) return deduped;
    return deduped.sublist(0, pageSize);
  }

  /// Takes several top USDA matches for [searchQuery], scales each to this line’s
  /// [amount]/[unit], then **averages** macros — typical values without picking a brand.
  Future<({Nutrition nutrition, bool estimated, int samplesUsed})?>
      averageNutritionForIngredient({
    required String searchQuery,
    required double amount,
    required String unit,
    required String ingredientName,
    int maxSamples = 5,
  }) async {
    final hits =
        await searchFoods(searchQuery, pageSize: maxSamples + 5);
    if (hits.isEmpty) return null;
    final samples = <Nutrition>[];
    var anyEst = false;
    for (final h in hits.take(maxSamples)) {
      try {
        final detail = await getFoodDetail(h.fdcId);
        final r = nutritionForIngredientFromFdcDetail(
          foodDetail: detail,
          amount: amount,
          unit: unit,
          ingredientName: ingredientName,
        );
        if (r != null) {
          samples.add(r.nutrition);
          if (r.estimated) anyEst = true;
        }
      } catch (_) {}
    }
    if (samples.isEmpty) return null;
    return (
      nutrition: averageNutrition(samples),
      estimated: anyEst,
      samplesUsed: samples.length,
    );
  }

  /// Full food record (Foundation, SR Legacy, Branded, etc.).
  Future<Map<String, dynamic>> getFoodDetail(int fdcId) async {
    if (!Env.hasFdc) {
      throw StateError('FDC_API_KEY is not configured.');
    }
    final uri = _apiRoot('/food/$fdcId', {'api_key': Env.fdcApiKey});
    return _client.getJson(uri);
  }
}
