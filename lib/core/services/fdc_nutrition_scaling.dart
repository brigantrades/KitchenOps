import 'package:plateplan/core/models/app_models.dart';

/// USDA FoodData Central nutrient ids (see FDC nutrient list).
abstract final class FdcNutrientIds {
  static const int energyKcal = 1008;
  static const int protein = 1003;
  static const int totalFat = 1004;
  static const int carbohydrate = 1005;
  static const int fiber = 1079;
  static const int sugars = 2000;
}

/// Builds [Nutrition] from FDC `foodNutrients` entries (detail endpoint).
/// [amount] values are merged by nutrient id (last wins for duplicates).
Nutrition nutritionFromFdcFoodNutrients(List<dynamic> raw) {
  var calories = 0;
  var protein = 0.0;
  var fat = 0.0;
  var carbs = 0.0;
  var fiber = 0.0;
  var sugar = 0.0;

  for (final entry in raw) {
    if (entry is! Map<String, dynamic>) continue;
    final nutrient = entry['nutrient'];
    if (nutrient is! Map<String, dynamic>) continue;
    final id = (nutrient['id'] as num?)?.toInt();
    final amount = (entry['amount'] as num?)?.toDouble();
    if (id == null || amount == null) continue;
    final unit = (nutrient['unitName'] as String?)?.toLowerCase() ?? '';
    if (id == FdcNutrientIds.energyKcal) {
      var kcal = amount;
      if (unit == 'kj') kcal = amount / 4.184;
      calories = kcal.round();
    } else if (id == FdcNutrientIds.protein) {
      protein = amount;
    } else if (id == FdcNutrientIds.totalFat) {
      fat = amount;
    } else if (id == FdcNutrientIds.carbohydrate) {
      carbs = amount;
    } else if (id == FdcNutrientIds.fiber) {
      fiber = amount;
    } else if (id == FdcNutrientIds.sugars) {
      sugar = amount;
    }
  }

  return ensureCaloriesFromMacrosIfMissing(
    Nutrition(
      calories: calories,
      protein: protein,
      fat: fat,
      carbs: carbs,
      fiber: fiber,
      sugar: sugar,
    ),
  );
}

/// When FDC omits Energy (1008) but macros exist, derive kcal (Atwater general).
Nutrition ensureCaloriesFromMacrosIfMissing(Nutrition n) {
  if (n.calories > 0) return n;
  if (n.protein == 0 && n.fat == 0 && n.carbs == 0) return n;
  final kcal = 4 * n.protein + 4 * n.carbs + 9 * n.fat;
  return Nutrition(
    calories: kcal.round().clamp(0, 1000000),
    protein: n.protein,
    fat: n.fat,
    carbs: n.carbs,
    fiber: n.fiber,
    sugar: n.sugar,
  );
}

Nutrition scaleNutritionPer100g(Nutrition per100g, double grams) {
  if (grams <= 0) return const Nutrition();
  final f = grams / 100.0;
  return Nutrition(
    calories: (per100g.calories * f).round(),
    protein: per100g.protein * f,
    fat: per100g.fat * f,
    carbs: per100g.carbs * f,
    fiber: per100g.fiber * f,
    sugar: per100g.sugar * f,
  );
}

Nutrition scaleNutritionProportional(Nutrition base, double factor) {
  if (factor <= 0) return const Nutrition();
  return Nutrition(
    calories: (base.calories * factor).round(),
    protein: base.protein * factor,
    fat: base.fat * factor,
    carbs: base.carbs * factor,
    fiber: base.fiber * factor,
    sugar: base.sugar * factor,
  );
}

/// Result of converting the user's amount + unit to grams for FDC scaling.
typedef FdcGramResolve = ({double? grams, bool estimated});

const double _mlPerUsCup = 236.588;
const double _mlPerTbsp = 14.7868;
const double _mlPerTsp = 4.92892;
const double _gPerOz = 28.349523125;
const double _gPerLb = 453.59237;

/// g/ml fallbacks when FDC portions don't match (volume → mass).
double _densityGPerMlHint(String ingredientNameLower) {
  if (ingredientNameLower.contains('oil') ||
      ingredientNameLower.contains('butter')) {
    return 0.92;
  }
  if (ingredientNameLower.contains('flour') ||
      ingredientNameLower.contains('sugar') && !ingredientNameLower.contains('syrup')) {
    return 0.55;
  }
  if (ingredientNameLower.contains('milk')) {
    return 1.03;
  }
  return 1.0;
}

double? _volumeToMl(double amount, String unitNorm) {
  switch (unitNorm) {
    case 'ml':
    case 'milliliter':
    case 'milliliters':
      return amount;
    case 'l':
    case 'liter':
    case 'liters':
      return amount * 1000;
    case 'cup':
    case 'cups':
      return amount * _mlPerUsCup;
    case 'tbsp':
    case 'tablespoon':
    case 'tablespoons':
      return amount * _mlPerTbsp;
    case 'tsp':
    case 'teaspoon':
    case 'teaspoons':
      return amount * _mlPerTsp;
    default:
      return null;
  }
}

/// Parses [foodPortions] from FDC food detail (list of maps).
double? _gramsFromFdcPortions(
  double amount,
  String unitRaw,
  List<dynamic> foodPortions,
) {
  final u = unitRaw.trim().toLowerCase();
  for (final p in foodPortions) {
    if (p is! Map<String, dynamic>) continue;
    final gw = (p['gramWeight'] as num?)?.toDouble();
    final portionAmount = (p['amount'] as num?)?.toDouble() ?? 1;
    if (gw == null || gw <= 0) continue;
    final measureUnit = p['measureUnit'];
    String? muName;
    if (measureUnit is Map<String, dynamic>) {
      muName = measureUnit['name']?.toString().toLowerCase() ?? '';
    }
    final desc = '${p['portionDescription'] ?? ''} $muName'.toLowerCase();
    bool matches = false;
    if (u == 'cup' || u == 'cups') {
      matches = desc.contains('cup');
    } else if (u == 'tbsp' || u == 'tablespoon' || u == 'tablespoons') {
      matches = desc.contains('tbsp') || desc.contains('tablespoon');
    } else if (u == 'tsp' || u == 'teaspoon' || u == 'teaspoons') {
      matches = desc.contains('tsp') || desc.contains('teaspoon');
    } else if (u == 'oz' || u == 'ounce' || u == 'ounces') {
      matches = desc.contains('oz') || desc.contains('ounce');
    } else if (u == 'g' || u == 'gram' || u == 'grams') {
      matches = desc.contains('g') && desc.contains('1');
    }
    if (matches) {
      return gw * (amount / portionAmount);
    }
  }
  return null;
}

/// Converts user [amount] + [unit] to grams, using FDC portions when possible.
FdcGramResolve resolveGramsForFdcFood({
  required double amount,
  required String unit,
  required String ingredientName,
  required Map<String, dynamic> foodDetail,
}) {
  final u = unit.trim().toLowerCase();
  if (amount <= 0) return (grams: null, estimated: false);

  final portions = foodDetail['foodPortions'] as List<dynamic>? ?? const [];

  switch (u) {
    case 'g':
    case 'gram':
    case 'grams':
      return (grams: amount, estimated: false);
    case 'kg':
    case 'kilogram':
    case 'kilograms':
      return (grams: amount * 1000, estimated: false);
    case 'mg':
    case 'milligram':
    case 'milligrams':
      return (grams: amount / 1000, estimated: false);
    case 'oz':
    case 'ounce':
    case 'ounces':
      return (grams: amount * _gPerOz, estimated: false);
    case 'lb':
    case 'lbs':
    case 'pound':
    case 'pounds':
      return (grams: amount * _gPerLb, estimated: false);
    case 'ml':
    case 'milliliter':
    case 'milliliters':
      return (grams: amount, estimated: true);
    case 'l':
    case 'liter':
    case 'liters':
      return (grams: amount * 1000, estimated: true);
  }

  final fromPortion = _gramsFromFdcPortions(amount, u, portions);
  if (fromPortion != null) {
    return (grams: fromPortion, estimated: false);
  }

  final ml = _volumeToMl(amount, u);
  if (ml != null) {
    final density = _densityGPerMlHint(ingredientName.toLowerCase());
    return (grams: ml * density, estimated: true);
  }

  if (u == 'piece' || u == 'pieces') {
    return (grams: null, estimated: false);
  }

  return (grams: null, estimated: false);
}

/// Whether FDC lists nutrients per 100 g edible portion for this food.
bool fdcFoodUsesPer100g(String? dataType) {
  final t = dataType?.toLowerCase() ?? '';
  return t == 'foundation' ||
      t.contains('sr legacy') ||
      t == 'survey (fndds)' ||
      t.contains('fndds');
}

/// Branded foods typically report nutrients per [servingSize] in [servingSizeUnit].
bool fdcFoodUsesPerServing(String? dataType) {
  final t = dataType?.toLowerCase() ?? '';
  return t == 'branded';
}

double? brandedServingGrams(Map<String, dynamic> foodDetail) {
  final size = (foodDetail['servingSize'] as num?)?.toDouble();
  if (size == null || size <= 0) return null;
  final unit = foodDetail['servingSizeUnit']?.toString().trim().toLowerCase() ?? 'g';
  switch (unit) {
    case 'g':
    case 'gram':
    case 'grams':
      return size;
    case 'ml':
    case 'milliliter':
    case 'milliliters':
      return size;
    case 'oz':
    case 'ounce':
    case 'ounces':
      return size * _gPerOz;
    default:
      return size;
  }
}

typedef FdcLineNutritionResult = ({Nutrition nutrition, bool estimated});

/// Sums [Ingredient.lineNutrition] for non-qualitative rows and sets a DB
/// `nutrition_source` when at least one line used FDC.
(Nutrition total, String? nutritionSource) aggregateFdcRecipeTotals(
  List<Ingredient> ingredients,
) {
  var total = const Nutrition();
  var nonQual = 0;
  var linked = 0;
  for (final i in ingredients) {
    if (i.qualitative) continue;
    nonQual++;
    if (i.lineNutrition != null &&
        (i.fdcId != null || i.fdcTypicalAverage)) {
      total += i.lineNutrition!;
      linked++;
    }
  }
  if (linked == 0) {
    return (total, null);
  }
  final source = linked >= nonQual ? 'fdc' : 'fdc_partial';
  return (total, source);
}

/// Arithmetic mean of [Nutrition] values (for typical/averaged USDA samples).
Nutrition averageNutrition(List<Nutrition> list) {
  if (list.isEmpty) return const Nutrition();
  final n = list.length;
  return Nutrition(
    calories: (list.fold<int>(0, (s, e) => s + e.calories) / n).round(),
    protein: list.fold(0.0, (s, e) => s + e.protein) / n,
    fat: list.fold(0.0, (s, e) => s + e.fat) / n,
    carbs: list.fold(0.0, (s, e) => s + e.carbs) / n,
    fiber: list.fold(0.0, (s, e) => s + e.fiber) / n,
    sugar: list.fold(0.0, (s, e) => s + e.sugar) / n,
  );
}

/// Computes line nutrition from a full FDC food detail payload + user amount/unit.
FdcLineNutritionResult? nutritionForIngredientFromFdcDetail({
  required Map<String, dynamic> foodDetail,
  required double amount,
  required String unit,
  required String ingredientName,
}) {
  final rawNutrients = foodDetail['foodNutrients'] as List<dynamic>? ?? const [];
  final base = nutritionFromFdcFoodNutrients(rawNutrients);
  final dataType = foodDetail['dataType']?.toString();
  final gramsResult = resolveGramsForFdcFood(
    amount: amount,
    unit: unit,
    ingredientName: ingredientName,
    foodDetail: foodDetail,
  );
  final grams = gramsResult.grams;
  if (grams == null) return null;

  var estimated = gramsResult.estimated;

  if (fdcFoodUsesPerServing(dataType)) {
    final serveG = brandedServingGrams(foodDetail);
    if (serveG != null && serveG > 0) {
      return (
        nutrition: scaleNutritionProportional(base, grams / serveG),
        estimated: estimated,
      );
    }
    return (
      nutrition: scaleNutritionPer100g(base, grams),
      estimated: true,
    );
  }

  if (fdcFoodUsesPer100g(dataType)) {
    return (nutrition: scaleNutritionPer100g(base, grams), estimated: estimated);
  }

  final serveG = brandedServingGrams(foodDetail);
  if (serveG != null && serveG > 0) {
    return (
      nutrition: scaleNutritionProportional(base, grams / serveG),
      estimated: estimated,
    );
  }

  return (nutrition: scaleNutritionPer100g(base, grams), estimated: true);
}
