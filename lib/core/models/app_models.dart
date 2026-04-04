import 'dart:convert';

import 'package:collection/collection.dart';
import 'package:plateplan/core/strings/ingredient_amount_display.dart';

/// Parses [recipes.cuisine_tags] from PostgREST / JSON (usually a [List], rarely a
/// JSON string). Empty list on unknown shapes so Discover matching still works.
List<String> recipeCuisineTagsFromJson(dynamic value) {
  if (value == null) return const [];
  if (value is List) {
    return value
        .map((e) => e.toString().trim())
        .where((s) => s.isNotEmpty)
        .toList();
  }
  if (value is String) {
    final s = value.trim();
    if (s.isEmpty) return const [];
    if (s.startsWith('[')) {
      try {
        final decoded = jsonDecode(s);
        if (decoded is List) {
          return decoded
              .map((e) => e.toString().trim())
              .where((e) => e.isNotEmpty)
              .toList();
        }
      } catch (_) {}
    }
  }
  return const [];
}

enum MealType { entree, side, sauce, snack, dessert }

enum GroceryCategory {
  produce,
  meatFish,
  dairyEggs,
  pantryGrains,
  bakery,
  other
}

enum RecipeVisibility { personal, household, public }

enum ListScope { private, household }

/// Backed by `lists.kind` in Postgres.
///
/// Keep as string constants (not an enum) so unknown kinds from future app
/// versions don't break older clients.
const String kListKindGeneral = 'general';
const String kListKindGrocery = 'grocery';

enum HouseholdRole { owner, member }

enum HouseholdMemberStatus { active, invited }

/// Planner strip: [startDay] is 0=Monday … 6=Sunday (matches `MealPlanSlot.dayOfWeek`).
/// [dayCount] is how many consecutive calendar days to show. Prev/next always move by one
/// calendar week (7 days) so the first column stays on [startDay] (e.g. Tue–Mon does not
/// drift to Wed–Tue when [dayCount] is 8).
class PlannerWindowPreference {
  const PlannerWindowPreference({
    required this.startDay,
    required this.dayCount,
  });

  /// Monday=0 … Sunday=6
  final int startDay;

  /// Number of consecutive days (1–14).
  final int dayCount;

  static const PlannerWindowPreference appDefault =
      PlannerWindowPreference(startDay: 0, dayCount: 7);

  /// One calendar week — keeps anchor aligned with [startDay] for weekly navigation.
  int get navigationStepDays => 7;

  bool get isValid =>
      startDay >= 0 && startDay <= 6 && dayCount >= 1 && dayCount <= 14;

  /// Shared by all household members; [appDefault] when not in a household.
  static PlannerWindowPreference resolve({required Household? household}) {
    if (household != null) {
      return PlannerWindowPreference(
        startDay: household.plannerStartDay,
        dayCount: household.plannerDayCount,
      );
    }
    return appDefault;
  }
}

extension GroceryCategoryX on GroceryCategory {
  String get label => switch (this) {
        GroceryCategory.produce => 'Produce',
        GroceryCategory.meatFish => 'Meat & Fish',
        GroceryCategory.dairyEggs => 'Dairy & Eggs',
        GroceryCategory.pantryGrains => 'Pantry / Grains',
        GroceryCategory.bakery => 'Bakery',
        GroceryCategory.other => 'Other',
      };

  String get dbValue => switch (this) {
        GroceryCategory.produce => 'produce',
        GroceryCategory.meatFish => 'meat',
        GroceryCategory.dairyEggs => 'dairy',
        GroceryCategory.pantryGrains => 'pantry',
        GroceryCategory.bakery => 'bakery',
        GroceryCategory.other => 'other',
      };
}

class Ingredient {
  const Ingredient({
    required this.name,
    required this.amount,
    required this.unit,
    required this.category,
    this.qualitative = false,
    this.fdcId,
    this.fdcDescription,
    this.lineNutrition,
    this.fdcNutritionEstimated = false,
    this.fdcTypicalAverage = false,
  });

  final String name;
  final double amount;
  final String unit;
  final GroceryCategory category;

  /// When true, [unit] holds the full amount phrase (e.g. "to taste", "1 tsp")
  /// and [amount] is typically 0; scaling for grocery uses [unit] as-is.
  final bool qualitative;

  /// USDA FoodData Central food id when the user linked this line to a food.
  final int? fdcId;

  /// Label shown for the linked FDC food (snapshot for display).
  final String? fdcDescription;

  /// Nutrition contributed by this line for the recipe as written (scaled amount).
  final Nutrition? lineNutrition;

  /// True when grams were inferred via volume/density fallback rather than FDC portions.
  final bool fdcNutritionEstimated;

  /// True when [lineNutrition] is the mean of several USDA matches (no single [fdcId]).
  final bool fdcTypicalAverage;

  /// Amount + unit for measured rows, or the qualitative phrase when [qualitative].
  String get quantityLabel {
    if (qualitative) return unit.trim();
    final amountLabel = formatIngredientAmount(amount);
    return '$amountLabel ${unit.trim()}'.trim();
  }

  Map<String, dynamic> toJson() => {
        'name': name,
        'amount': amount,
        'unit': unit,
        'category': category.dbValue,
        if (qualitative) 'qualitative': true,
        if (fdcId != null) 'fdc_id': fdcId,
        if (fdcDescription != null && fdcDescription!.isNotEmpty)
          'fdc_description': fdcDescription,
        if (lineNutrition != null) 'nutrition': lineNutrition!.toJson(),
        if (fdcNutritionEstimated) 'fdc_nutrition_estimated': true,
        if (fdcTypicalAverage) 'fdc_typical_average': true,
      };

  factory Ingredient.fromJson(Map<String, dynamic> json) => Ingredient(
        name: json['name']?.toString() ?? '',
        amount: (json['amount'] as num?)?.toDouble() ?? 0,
        unit: json['unit']?.toString() ?? '',
        category: GroceryCategory.values.firstWhereOrNull(
              (c) => c.dbValue == json['category'],
            ) ??
            GroceryCategory.other,
        qualitative: json['qualitative'] as bool? ?? false,
        fdcId: (json['fdc_id'] as num?)?.toInt(),
        fdcDescription: json['fdc_description']?.toString(),
        lineNutrition: json['nutrition'] is Map<String, dynamic>
            ? Nutrition.fromJson(json['nutrition'] as Map<String, dynamic>)
            : null,
        fdcNutritionEstimated: json['fdc_nutrition_estimated'] == true,
        fdcTypicalAverage: json['fdc_typical_average'] == true,
      );
}

class Nutrition {
  const Nutrition({
    this.calories = 0,
    this.protein = 0,
    this.fat = 0,
    this.carbs = 0,
    this.fiber = 0,
    this.sugar = 0,
  });

  final int calories;
  final double protein;
  final double fat;
  final double carbs;
  final double fiber;
  final double sugar;

  Map<String, dynamic> toJson() => {
        'calories': calories,
        'protein': protein,
        'fat': fat,
        'carbs': carbs,
        'fiber': fiber,
        'sugar': sugar,
      };

  factory Nutrition.fromJson(Map<String, dynamic>? json) => Nutrition(
        calories: (json?['calories'] as num?)?.toInt() ?? 0,
        protein: (json?['protein'] as num?)?.toDouble() ?? 0,
        fat: (json?['fat'] as num?)?.toDouble() ?? 0,
        carbs: (json?['carbs'] as num?)?.toDouble() ?? 0,
        fiber: (json?['fiber'] as num?)?.toDouble() ?? 0,
        sugar: (json?['sugar'] as num?)?.toDouble() ?? 0,
      );

  Nutrition operator +(Nutrition other) => Nutrition(
        calories: calories + other.calories,
        protein: protein + other.protein,
        fat: fat + other.fat,
        carbs: carbs + other.carbs,
        fiber: fiber + other.fiber,
        sugar: sugar + other.sugar,
      );
}

/// Sauce or icing stored on the main recipe row (not a separate [MealType.sauce] recipe).
class RecipeEmbeddedSauce {
  const RecipeEmbeddedSauce({
    this.title,
    this.ingredients = const [],
    this.instructions = const [],
  });

  final String? title;
  final List<Ingredient> ingredients;
  final List<String> instructions;

  Map<String, dynamic> toJson() => {
        if (title != null && title!.trim().isNotEmpty) 'title': title,
        'ingredients': ingredients.map((e) => e.toJson()).toList(),
        'instructions': instructions,
      };

  factory RecipeEmbeddedSauce.fromJson(Map<String, dynamic>? json) {
    if (json == null) {
      return const RecipeEmbeddedSauce();
    }
    return RecipeEmbeddedSauce(
      title: json['title']?.toString(),
      ingredients: (json['ingredients'] as List?)
              ?.whereType<Map<String, dynamic>>()
              .map(Ingredient.fromJson)
              .toList() ??
          const [],
      instructions:
          (json['instructions'] as List?)?.map((e) => e.toString()).toList() ??
              const [],
    );
  }
}

class Recipe {
  const Recipe({
    required this.id,
    required this.title,
    this.description,
    this.servings = 2,
    this.prepTime,
    this.cookTime,
    required this.mealType,
    this.cuisineTags = const [],
    this.ingredients = const [],
    this.instructions = const [],
    this.imageUrl,
    this.nutrition = const Nutrition(),
    this.isFavorite = false,
    this.isToTry = false,
    this.source = 'user_created',
    this.sourceUrl,
    this.userId,
    this.householdId,
    this.visibility = RecipeVisibility.personal,
    this.apiId,
    this.nutritionSource,
    this.copiedFromPersonalRecipeId,
    this.createdAt,
    this.defaultSauceRecipeId,
    this.embeddedSauce,
  });

  final String id;
  final String title;
  final String? description;
  final int servings;
  final int? prepTime;
  final int? cookTime;
  final MealType mealType;
  final List<String> cuisineTags;
  final List<Ingredient> ingredients;
  final List<String> instructions;
  final String? imageUrl;
  final Nutrition nutrition;
  final bool isFavorite;
  final bool isToTry;
  final String source;
  final String? sourceUrl;
  final String? userId;
  final String? householdId;
  final RecipeVisibility visibility;

  /// Spoonacular / discover id; unique in DB — must be preserved on edit.
  final String? apiId;

  /// e.g. `fdc`, `fdc_partial`, `spoonacular`, `user` — mirrors `nutrition_source` in DB.
  final String? nutritionSource;

  /// Personal recipe id this household row was copied from (share-to-household), if any.
  final String? copiedFromPersonalRecipeId;
  final DateTime? createdAt;

  /// Optional linked sauce/icing recipe ([MealType.sauce]) suggested for this dish.
  /// Prefer [embeddedSauce] for user-authored entrees (single recipe row).
  final String? defaultSauceRecipeId;

  /// Sauce or icing content stored on this recipe (same servings as main).
  final RecipeEmbeddedSauce? embeddedSauce;

  Recipe copyWith({
    String? id,
    String? title,
    String? description,
    int? servings,
    int? prepTime,
    int? cookTime,
    bool clearPrepTime = false,
    bool clearCookTime = false,
    MealType? mealType,
    List<String>? cuisineTags,
    List<Ingredient>? ingredients,
    List<String>? instructions,
    String? imageUrl,
    bool clearImageUrl = false,
    Nutrition? nutrition,
    bool? isFavorite,
    bool? isToTry,
    String? source,
    String? sourceUrl,
    String? userId,
    String? householdId,
    RecipeVisibility? visibility,
    String? apiId,
    String? nutritionSource,
    String? copiedFromPersonalRecipeId,
    DateTime? createdAt,
    String? defaultSauceRecipeId,
    bool clearDefaultSauceRecipeId = false,
    RecipeEmbeddedSauce? embeddedSauce,
    bool clearEmbeddedSauce = false,
  }) =>
      Recipe(
        id: id ?? this.id,
        title: title ?? this.title,
        description: description ?? this.description,
        servings: servings ?? this.servings,
        prepTime: clearPrepTime ? null : (prepTime ?? this.prepTime),
        cookTime: clearCookTime ? null : (cookTime ?? this.cookTime),
        mealType: mealType ?? this.mealType,
        cuisineTags: cuisineTags ?? this.cuisineTags,
        ingredients: ingredients ?? this.ingredients,
        instructions: instructions ?? this.instructions,
        imageUrl: clearImageUrl ? null : (imageUrl ?? this.imageUrl),
        nutrition: nutrition ?? this.nutrition,
        isFavorite: isFavorite ?? this.isFavorite,
        isToTry: isToTry ?? this.isToTry,
        source: source ?? this.source,
        sourceUrl: sourceUrl ?? this.sourceUrl,
        userId: userId ?? this.userId,
        householdId: householdId ?? this.householdId,
        visibility: visibility ?? this.visibility,
        apiId: apiId ?? this.apiId,
        nutritionSource: nutritionSource ?? this.nutritionSource,
        copiedFromPersonalRecipeId:
            copiedFromPersonalRecipeId ?? this.copiedFromPersonalRecipeId,
        createdAt: createdAt ?? this.createdAt,
        defaultSauceRecipeId: clearDefaultSauceRecipeId
            ? null
            : (defaultSauceRecipeId ?? this.defaultSauceRecipeId),
        embeddedSauce:
            clearEmbeddedSauce ? null : (embeddedSauce ?? this.embeddedSauce),
      );

  Map<String, dynamic> toJson() => {
        'id': id,
        'title': title,
        'description': description,
        'servings': servings,
        'prep_time': prepTime,
        'cook_time': cookTime,
        'meal_type': mealType.name,
        'cuisine_tags': cuisineTags,
        'ingredients': ingredients.map((e) => e.toJson()).toList(),
        'instructions': instructions,
        'image_url': imageUrl,
        'nutrition': nutrition.toJson(),
        'is_favorite': isFavorite,
        'is_to_try': isToTry,
        'source': source,
        'source_url': sourceUrl,
        'user_id': userId,
        'household_id': householdId,
        'visibility': visibility.name,
        'api_id': apiId,
        if (nutritionSource != null && nutritionSource!.isNotEmpty)
          'nutrition_source': nutritionSource,
        if (copiedFromPersonalRecipeId != null &&
            copiedFromPersonalRecipeId!.isNotEmpty)
          'copied_from_personal_recipe_id': copiedFromPersonalRecipeId,
        'default_sauce_recipe_id': defaultSauceRecipeId,
        'embedded_sauce': embeddedSauce?.toJson(),
      };

  factory Recipe.fromJson(Map<String, dynamic> json) => Recipe(
        id: json['id'].toString(),
        title: json['title']?.toString() ?? '',
        description: json['description']?.toString(),
        servings: (json['servings'] as num?)?.toInt() ?? 2,
        prepTime: (json['prep_time'] as num?)?.toInt(),
        cookTime: (json['cook_time'] as num?)?.toInt(),
        mealType: _mealTypeFromDb(json['meal_type']?.toString()),
        cuisineTags: recipeCuisineTagsFromJson(json['cuisine_tags']),
        ingredients: (json['ingredients'] as List?)
                ?.whereType<Map<String, dynamic>>()
                .map(Ingredient.fromJson)
                .toList() ??
            const [],
        instructions: (json['instructions'] as List?)
                ?.map((e) => e.toString())
                .toList() ??
            const [],
        imageUrl: json['image_url']?.toString(),
        nutrition:
            Nutrition.fromJson(json['nutrition'] as Map<String, dynamic>?),
        isFavorite: json['is_favorite'] == true,
        isToTry: json['is_to_try'] == true,
        source: json['source']?.toString() ?? 'user_created',
        sourceUrl: json['source_url']?.toString(),
        userId: json['user_id']?.toString(),
        householdId: json['household_id']?.toString(),
        visibility: RecipeVisibility.values.firstWhereOrNull(
              (v) => v.name == json['visibility'],
            ) ??
            RecipeVisibility.personal,
        apiId: json['api_id']?.toString(),
        nutritionSource: json['nutrition_source']?.toString(),
        copiedFromPersonalRecipeId:
            json['copied_from_personal_recipe_id']?.toString(),
        createdAt: DateTime.tryParse(json['created_at']?.toString() ?? ''),
        defaultSauceRecipeId: json['default_sauce_recipe_id']?.toString(),
        embeddedSauce: json['embedded_sauce'] is Map
            ? RecipeEmbeddedSauce.fromJson(
                Map<String, dynamic>.from(json['embedded_sauce'] as Map),
              )
            : null,
      );
}

/// Custom ingredient lines for a planner slot (text-only meals); persisted for the grocery sheet.
class PlannerGroceryDraftLine {
  const PlannerGroceryDraftLine({
    required this.name,
    this.quantity = 1,
  });

  final String name;
  final int quantity;

  Map<String, dynamic> toJson() => {
        'name': name,
        'quantity': quantity,
      };

  factory PlannerGroceryDraftLine.fromJson(Map<String, dynamic> json) =>
      PlannerGroceryDraftLine(
        name: json['name']?.toString() ?? '',
        quantity: (json['quantity'] as num?)?.toInt() ?? 1,
      );

  static List<PlannerGroceryDraftLine> listFromJson(dynamic raw) {
    if (raw == null) return const [];
    if (raw is! List) return const [];
    return raw
        .whereType<Map>()
        .map((e) =>
            PlannerGroceryDraftLine.fromJson(Map<String, dynamic>.from(e)))
        .where((e) => e.name.trim().isNotEmpty)
        .toList();
  }

  static List<Map<String, dynamic>> toJsonList(
          List<PlannerGroceryDraftLine> lines) =>
      lines.map((e) => e.toJson()).toList();
}

class PlannerSlotSideItem {
  const PlannerSlotSideItem({
    this.recipeId,
    this.text,
  });

  final String? recipeId;
  final String? text;

  bool get isEmpty =>
      (recipeId == null || recipeId!.trim().isEmpty) &&
      (text == null || text!.trim().isEmpty);

  Map<String, dynamic> toJson() => {
        'recipe_id': recipeId,
        'text': text?.trim().isEmpty == true ? null : text?.trim(),
      };

  factory PlannerSlotSideItem.fromJson(Map<String, dynamic> json) =>
      PlannerSlotSideItem(
        recipeId: json['recipe_id']?.toString(),
        text: json['text']?.toString(),
      );

  static List<PlannerSlotSideItem> listFromJson(dynamic raw) {
    if (raw == null || raw is! List) return const [];
    return raw
        .whereType<Map>()
        .map((e) => PlannerSlotSideItem.fromJson(Map<String, dynamic>.from(e)))
        .where((e) => !e.isEmpty)
        .toList();
  }

  static List<Map<String, dynamic>> toJsonList(
          List<PlannerSlotSideItem> items) =>
      items.where((e) => !e.isEmpty).map((e) => e.toJson()).toList();
}

/// Parses Postgres [`meal_plan_slots.week_start`] as a **local calendar date**.
///
/// Supabase often returns `YYYY-MM-DDT00:00:00Z`. Using [DateTime.parse] alone
/// makes [weekStart] UTC midnight, and [plannerDateOnly] then shifts to the
/// previous calendar day in negative UTC offsets — so [calendarDateForSlot]
/// maps slots to the wrong day and UI filters hide every row for the tapped day.
DateTime mealPlanWeekStartFromJson(dynamic raw) {
  final s = raw.toString();
  final head = s.split('T').first;
  final parts = head.split('-');
  if (parts.length == 3) {
    return DateTime(
      int.parse(parts[0]),
      int.parse(parts[1]),
      int.parse(parts[2]),
    );
  }
  final dt = DateTime.parse(s);
  final l = dt.toLocal();
  return DateTime(l.year, l.month, l.day);
}

/// Coerces [`meal_plan_slots.meal_type`] from PostgREST (almost always a [String]).
/// In edge cases a nested value can surface as [Map]; avoid `toString()` map blobs.
String mealPlanSlotMealLabelFromJson(dynamic value) {
  if (value == null) return 'meal';
  if (value is String) return value;
  if (value is Map) {
    final inner = value['meal_type'] ?? value['label'] ?? value['value'];
    if (inner is String) return inner;
    if (inner != null) return inner.toString();
  }
  return value.toString();
}

class MealPlanSlot {
  const MealPlanSlot({
    required this.id,
    required this.weekStart,
    required this.dayOfWeek,
    required this.mealLabel,
    this.recipeId,
    this.mealText,
    this.sideRecipeId,
    this.sideText,
    this.sideItems = const [],
    this.sauceRecipeId,
    this.sauceText,
    this.servingsUsed = 1,
    this.slotOrder = 0,
    this.reminderAt,
    this.reminderMessage,
    this.groceryDraftLines = const [],
    this.assignedUserIds = const [],
  });

  final String id;
  final DateTime weekStart;
  final int dayOfWeek;
  final String mealLabel;
  final String? recipeId;
  final String? mealText;
  final String? sideRecipeId;
  final String? sideText;
  final List<PlannerSlotSideItem> sideItems;
  final String? sauceRecipeId;
  final String? sauceText;
  final int servingsUsed;
  final int slotOrder;
  final DateTime? reminderAt;
  final String? reminderMessage;
  final List<PlannerGroceryDraftLine> groceryDraftLines;
  final List<String> assignedUserIds;

  bool get hasPlannedContent {
    final hasMealText = (mealText ?? '').trim().isNotEmpty;
    final hasSideText = (sideText ?? '').trim().isNotEmpty;
    final hasSauceText = (sauceText ?? '').trim().isNotEmpty;
    return recipeId != null ||
        hasMealText ||
        sideRecipeId != null ||
        hasSideText ||
        sideItems.isNotEmpty ||
        sauceRecipeId != null ||
        hasSauceText;
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'week_start': weekStart.toIso8601String().split('T').first,
        'day_of_week': dayOfWeek,
        'meal_type': mealLabel,
        'recipe_id': recipeId,
        'meal_text': mealText,
        'side_recipe_id': sideRecipeId,
        'side_text': sideText,
        'side_items': PlannerSlotSideItem.toJsonList(sideItems),
        'sauce_recipe_id': sauceRecipeId,
        'sauce_text': sauceText,
        'servings_used': servingsUsed,
        'slot_order': slotOrder,
        'reminder_at': reminderAt?.toUtc().toIso8601String(),
        'reminder_message': reminderMessage,
        'grocery_draft_lines':
            PlannerGroceryDraftLine.toJsonList(groceryDraftLines),
        'assigned_user_ids': assignedUserIds,
      };

  factory MealPlanSlot.fromJson(Map<String, dynamic> json) => MealPlanSlot(
        id: json['id'].toString(),
        weekStart: mealPlanWeekStartFromJson(json['week_start']),
        dayOfWeek: (json['day_of_week'] as num).toInt(),
        mealLabel: mealPlanSlotMealLabelFromJson(json['meal_type']),
        recipeId: json['recipe_id']?.toString(),
        mealText: json['meal_text']?.toString(),
        sideRecipeId: json['side_recipe_id']?.toString(),
        sideText: json['side_text']?.toString(),
        sideItems: () {
          final parsed = PlannerSlotSideItem.listFromJson(json['side_items']);
          if (parsed.isNotEmpty) return parsed;
          final legacyRecipeId = json['side_recipe_id']?.toString();
          final legacyText = json['side_text']?.toString();
          final legacy = PlannerSlotSideItem(
            recipeId: legacyRecipeId,
            text: legacyText,
          );
          return legacy.isEmpty
              ? const <PlannerSlotSideItem>[]
              : <PlannerSlotSideItem>[legacy];
        }(),
        sauceRecipeId: json['sauce_recipe_id']?.toString(),
        sauceText: json['sauce_text']?.toString(),
        servingsUsed: (json['servings_used'] as num?)?.toInt() ?? 1,
        slotOrder: (json['slot_order'] as num?)?.toInt() ?? 0,
        reminderAt: json['reminder_at'] != null
            ? DateTime.parse(json['reminder_at'].toString()).toUtc()
            : null,
        reminderMessage: json['reminder_message']?.toString(),
        groceryDraftLines:
            PlannerGroceryDraftLine.listFromJson(json['grocery_draft_lines']),
        assignedUserIds: (json['assigned_user_ids'] as List?)
                ?.map((e) => e.toString())
                .toList() ??
            const [],
      );

  MealPlanSlot copyWith({
    String? id,
    DateTime? weekStart,
    int? dayOfWeek,
    String? mealLabel,
    String? recipeId,
    String? mealText,
    String? sideRecipeId,
    String? sideText,
    List<PlannerSlotSideItem>? sideItems,
    String? sauceRecipeId,
    String? sauceText,
    int? servingsUsed,
    int? slotOrder,
    DateTime? reminderAt,
    String? reminderMessage,
    List<PlannerGroceryDraftLine>? groceryDraftLines,
    List<String>? assignedUserIds,
  }) =>
      MealPlanSlot(
        id: id ?? this.id,
        weekStart: weekStart ?? this.weekStart,
        dayOfWeek: dayOfWeek ?? this.dayOfWeek,
        mealLabel: mealLabel ?? this.mealLabel,
        recipeId: recipeId ?? this.recipeId,
        mealText: mealText ?? this.mealText,
        sideRecipeId: sideRecipeId ?? this.sideRecipeId,
        sideText: sideText ?? this.sideText,
        sideItems: sideItems ?? this.sideItems,
        sauceRecipeId: sauceRecipeId ?? this.sauceRecipeId,
        sauceText: sauceText ?? this.sauceText,
        servingsUsed: servingsUsed ?? this.servingsUsed,
        slotOrder: slotOrder ?? this.slotOrder,
        reminderAt: reminderAt ?? this.reminderAt,
        reminderMessage: reminderMessage ?? this.reminderMessage,
        groceryDraftLines: groceryDraftLines ?? this.groceryDraftLines,
        assignedUserIds: assignedUserIds ?? this.assignedUserIds,
      );
}

/// Matches `list_items.status` in Postgres (`open` | `done`).
enum GroceryItemStatus {
  open,
  done;

  static GroceryItemStatus fromDb(String? raw) {
    if (raw == null) return GroceryItemStatus.open;
    return GroceryItemStatus.values.firstWhereOrNull(
          (e) => e.name == raw,
        ) ??
        GroceryItemStatus.open;
  }

  String get dbValue => name;
}

class GroceryItem {
  const GroceryItem({
    required this.id,
    required this.name,
    required this.category,
    this.quantity,
    this.unit,
    this.fromRecipeId,
    this.listId,
    this.sourceSlotId,
    this.addedByUserId,
    this.status = GroceryItemStatus.open,
  });

  final String id;
  final String name;
  final GroceryCategory category;
  final String? quantity;
  final String? unit;
  final String? fromRecipeId;
  final String? listId;
  final String? sourceSlotId;

  /// Profile id of the member who added this row (list_items.user_id).
  final String? addedByUserId;

  /// `list_items.status`: open = still to buy, done = purchased / checked off.
  final GroceryItemStatus status;

  bool get fromPlanner => fromRecipeId != null;

  bool get isDone => status == GroceryItemStatus.done;

  GroceryItem copyWith({
    String? id,
    String? name,
    GroceryCategory? category,
    String? quantity,
    String? unit,
    String? fromRecipeId,
    String? listId,
    String? sourceSlotId,
    String? addedByUserId,
    GroceryItemStatus? status,
  }) {
    return GroceryItem(
      id: id ?? this.id,
      name: name ?? this.name,
      category: category ?? this.category,
      quantity: quantity ?? this.quantity,
      unit: unit ?? this.unit,
      fromRecipeId: fromRecipeId ?? this.fromRecipeId,
      listId: listId ?? this.listId,
      sourceSlotId: sourceSlotId ?? this.sourceSlotId,
      addedByUserId: addedByUserId ?? this.addedByUserId,
      status: status ?? this.status,
    );
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'name': name,
        'category': category.dbValue,
        'quantity': quantity,
        'unit': unit,
        'from_recipe_id': fromRecipeId,
        'list_id': listId,
        'source_slot_id': sourceSlotId,
        'status': status.dbValue,
        if (addedByUserId != null) 'user_id': addedByUserId,
      };

  factory GroceryItem.fromJson(Map<String, dynamic> json) => GroceryItem(
        id: json['id'].toString(),
        name: json['name']?.toString() ?? '',
        category: GroceryCategory.values.firstWhereOrNull(
              (c) => c.dbValue == json['category'],
            ) ??
            GroceryCategory.other,
        quantity: json['quantity']?.toString(),
        unit: json['unit']?.toString(),
        fromRecipeId: json['from_recipe_id']?.toString(),
        listId: json['list_id']?.toString(),
        sourceSlotId: json['source_slot_id']?.toString(),
        addedByUserId: json['user_id']?.toString(),
        status: GroceryItemStatus.fromDb(json['status']?.toString()),
      );
}

/// Normalized name for deduping grocery items (trim, lower, collapse spaces).
String normalizeGroceryItemName(String value) {
  return value.trim().toLowerCase().replaceAll(RegExp(r'\s+'), ' ');
}

class RecentGroceryEntry {
  const RecentGroceryEntry({
    required this.name,
    required this.category,
    this.quantity,
    this.unit,
    required this.lastUsedAt,
  });

  final String name;
  final GroceryCategory category;
  final String? quantity;
  final String? unit;
  final DateTime lastUsedAt;

  Map<String, dynamic> toJson() => {
        'name': name,
        'category': category.dbValue,
        if (quantity != null) 'quantity': quantity,
        if (unit != null) 'unit': unit,
        'last_used_at': lastUsedAt.toIso8601String(),
      };

  factory RecentGroceryEntry.fromJson(Map<String, dynamic> json) {
    return RecentGroceryEntry(
      name: json['name']?.toString() ?? '',
      category: GroceryCategory.values.firstWhereOrNull(
            (c) => c.dbValue == json['category'],
          ) ??
          GroceryCategory.other,
      quantity: json['quantity']?.toString(),
      unit: json['unit']?.toString(),
      lastUsedAt: DateTime.tryParse(json['last_used_at']?.toString() ?? '') ??
          DateTime.now().toUtc(),
    );
  }
}

class AppList {
  const AppList({
    required this.id,
    required this.name,
    required this.kind,
    required this.scope,
    this.householdId,
    required this.ownerUserId,
    this.createdAt,
  });

  final String id;
  final String name;
  final String kind;
  final ListScope scope;
  final String? householdId;
  final String ownerUserId;
  final DateTime? createdAt;

  factory AppList.fromJson(Map<String, dynamic> json) => AppList(
        id: json['id'].toString(),
        name: json['name']?.toString() ?? 'List',
        kind: json['kind']?.toString() ?? 'general',
        scope: ListScope.values.firstWhereOrNull(
              (s) => s.name == json['scope'],
            ) ??
            ListScope.private,
        householdId: json['household_id']?.toString(),
        ownerUserId: json['owner_user_id']?.toString() ?? '',
        createdAt: json['created_at'] != null
            ? DateTime.tryParse(json['created_at'].toString())
            : null,
      );
}

/// Saved on `profiles.grocery_list_order` (per-user list ordering).
class GroceryListOrder {
  const GroceryListOrder({
    this.privateIds = const [],
    this.householdIds = const [],
  });

  final List<String> privateIds;
  final List<String> householdIds;

  static const empty = GroceryListOrder();

  List<String> idsFor(ListScope scope) =>
      scope == ListScope.private ? privateIds : householdIds;

  GroceryListOrder withIdsFor(ListScope scope, List<String> ids) {
    if (scope == ListScope.private) {
      return GroceryListOrder(privateIds: ids, householdIds: householdIds);
    }
    return GroceryListOrder(privateIds: privateIds, householdIds: ids);
  }

  Map<String, dynamic> toJsonColumn() => {
        ListScope.private.name: privateIds,
        ListScope.household.name: householdIds,
      };

  factory GroceryListOrder.fromJson(dynamic json) {
    if (json == null || json is! Map) return const GroceryListOrder();
    final m = Map<String, dynamic>.from(json);
    List<String> parse(String key) =>
        (m[key] as List?)?.map((e) => e.toString()).toList() ?? const [];
    return GroceryListOrder(
      privateIds: parse(ListScope.private.name),
      householdIds: parse(ListScope.household.name),
    );
  }
}

MealType _mealTypeFromDb(String? value) {
  final raw = (value ?? '').trim().toLowerCase();
  switch (raw) {
    case 'breakfast':
    case 'entree':
      return MealType.entree;
    case 'lunch':
    case 'side':
      return MealType.side;
    case 'dinner':
    case 'sauce':
      return MealType.sauce;
    case 'snack':
      return MealType.snack;
    case 'dessert':
      return MealType.dessert;
    default:
      return MealType.entree;
  }
}

class Profile {
  const Profile({
    required this.id,
    required this.name,
    this.avatarUrl,
    this.goals = const [],
    this.dietaryRestrictions = const [],
    this.preferredCuisines = const [],
    this.dislikedIngredients = const [],
    this.householdServings,
    this.householdId,
    this.groceryListOrder = GroceryListOrder.empty,
  });

  final String id;
  final String name;
  final String? avatarUrl;
  final List<String> goals;
  final List<String> dietaryRestrictions;
  final List<String> preferredCuisines;
  final List<String> dislikedIngredients;
  final int? householdServings;
  final String? householdId;
  final GroceryListOrder groceryListOrder;

  Map<String, dynamic> toJson() => {
        'id': id,
        'name': name,
        'avatar_url': avatarUrl,
        'goals': goals,
        'dietary_restrictions': dietaryRestrictions,
        'preferred_cuisines': preferredCuisines,
        'disliked_ingredients': dislikedIngredients,
        'household_servings': householdServings,
        'household_id': householdId,
      };

  factory Profile.fromJson(Map<String, dynamic> json) => Profile(
        id: json['id'].toString(),
        name: json['name']?.toString() ?? '',
        avatarUrl: json['avatar_url']?.toString(),
        goals: (json['goals'] as List?)?.map((e) => e.toString()).toList() ??
            const [],
        dietaryRestrictions: (json['dietary_restrictions'] as List?)
                ?.map((e) => e.toString())
                .toList() ??
            const [],
        preferredCuisines: (json['preferred_cuisines'] as List?)
                ?.map((e) => e.toString())
                .toList() ??
            const [],
        dislikedIngredients: (json['disliked_ingredients'] as List?)
                ?.map((e) => e.toString())
                .toList() ??
            const [],
        householdServings: (json['household_servings'] as num?)?.toInt(),
        householdId: json['household_id']?.toString(),
        groceryListOrder: GroceryListOrder.fromJson(json['grocery_list_order']),
      );

  Profile copyWith({
    String? id,
    String? name,
    String? avatarUrl,
    List<String>? goals,
    List<String>? dietaryRestrictions,
    List<String>? preferredCuisines,
    List<String>? dislikedIngredients,
    int? householdServings,
    String? householdId,
    GroceryListOrder? groceryListOrder,
  }) {
    return Profile(
      id: id ?? this.id,
      name: name ?? this.name,
      avatarUrl: avatarUrl ?? this.avatarUrl,
      goals: goals ?? this.goals,
      dietaryRestrictions: dietaryRestrictions ?? this.dietaryRestrictions,
      preferredCuisines: preferredCuisines ?? this.preferredCuisines,
      dislikedIngredients: dislikedIngredients ?? this.dislikedIngredients,
      householdServings: householdServings ?? this.householdServings,
      householdId: householdId ?? this.householdId,
      groceryListOrder: groceryListOrder ?? this.groceryListOrder,
    );
  }
}

class Household {
  const Household({
    required this.id,
    required this.name,
    required this.createdBy,
    this.plannerStartDay = 0,
    this.plannerDayCount = 7,
  });

  final String id;
  final String name;
  final String createdBy;

  /// Default planner start day (0=Mon..6=Sun) for members who follow household.
  final int plannerStartDay;

  /// Default planner day count for members who follow household.
  final int plannerDayCount;

  factory Household.fromJson(Map<String, dynamic> json) => Household(
        id: json['id'].toString(),
        name: json['name']?.toString() ?? 'My Household',
        createdBy: json['created_by']?.toString() ?? '',
        plannerStartDay: (json['planner_start_day'] as num?)?.toInt() ?? 0,
        plannerDayCount: (json['planner_day_count'] as num?)?.toInt() ?? 7,
      );

  Household copyWith({
    String? id,
    String? name,
    String? createdBy,
    int? plannerStartDay,
    int? plannerDayCount,
  }) {
    return Household(
      id: id ?? this.id,
      name: name ?? this.name,
      createdBy: createdBy ?? this.createdBy,
      plannerStartDay: plannerStartDay ?? this.plannerStartDay,
      plannerDayCount: plannerDayCount ?? this.plannerDayCount,
    );
  }
}

class HouseholdMember {
  const HouseholdMember({
    required this.householdId,
    required this.userId,
    required this.role,
    required this.status,
    this.name,
    this.invitedEmail,
  });

  final String householdId;
  final String userId;
  final HouseholdRole role;
  final HouseholdMemberStatus status;
  final String? name;
  final String? invitedEmail;

  /// Household member label from profile name only.
  String get displayName {
    final n = name?.trim() ?? '';
    if (n.isNotEmpty) return n;
    return 'Unknown user';
  }

  factory HouseholdMember.fromJson(Map<String, dynamic> json) {
    final rawProfile = json['profiles'];
    Map<String, dynamic>? profile;
    if (rawProfile is Map<String, dynamic>) {
      profile = rawProfile;
    } else if (rawProfile is List && rawProfile.isNotEmpty) {
      final first = rawProfile.first;
      if (first is Map) {
        profile = Map<String, dynamic>.from(first);
      }
    }
    return HouseholdMember(
      householdId: json['household_id'].toString(),
      userId: json['user_id'].toString(),
      role: HouseholdRole.values.firstWhereOrNull(
            (role) => role.name == json['role'],
          ) ??
          HouseholdRole.member,
      status: HouseholdMemberStatus.values.firstWhereOrNull(
            (status) => status.name == json['status'],
          ) ??
          HouseholdMemberStatus.active,
      name: profile?['name']?.toString(),
      invitedEmail: json['invited_email']?.toString(),
    );
  }
}

class HouseholdInvite {
  const HouseholdInvite({
    required this.householdId,
    required this.householdName,
    required this.role,
    this.invitedEmail,
    this.invitedByEmail,
  });

  final String householdId;
  final String householdName;
  final HouseholdRole role;

  /// Email address the invite was sent to (the invitee).
  final String? invitedEmail;

  /// Account email of the user who sent the invite.
  final String? invitedByEmail;

  factory HouseholdInvite.fromJson(Map<String, dynamic> json) {
    final household = json['households'] as Map<String, dynamic>?;
    return HouseholdInvite(
      householdId: json['household_id'].toString(),
      householdName: household?['name']?.toString() ?? 'Household',
      role: HouseholdRole.values.firstWhereOrNull(
            (role) => role.name == json['role'],
          ) ??
          HouseholdRole.member,
      invitedEmail: json['invited_email']?.toString(),
      invitedByEmail: json['invited_by_email']?.toString(),
    );
  }
}

class PantryItem {
  const PantryItem({
    required this.id,
    required this.householdId,
    required this.name,
    required this.category,
    required this.currentQuantity,
    required this.unit,
    this.bufferThreshold,
    this.fdcId,
    this.lastAuditAt,
    this.sortOrder = 0,
    this.createdBy,
    this.createdAt,
    this.updatedAt,
  });

  final String id;
  final String householdId;
  final String name;
  final GroceryCategory category;
  final double currentQuantity;
  final String unit;
  final double? bufferThreshold;
  final int? fdcId;
  final DateTime? lastAuditAt;
  final int sortOrder;
  final String? createdBy;
  final DateTime? createdAt;
  final DateTime? updatedAt;

  PantryItem copyWith({
    String? id,
    String? householdId,
    String? name,
    GroceryCategory? category,
    double? currentQuantity,
    String? unit,
    double? bufferThreshold,
    int? fdcId,
    DateTime? lastAuditAt,
    int? sortOrder,
    String? createdBy,
    DateTime? createdAt,
    DateTime? updatedAt,
  }) {
    return PantryItem(
      id: id ?? this.id,
      householdId: householdId ?? this.householdId,
      name: name ?? this.name,
      category: category ?? this.category,
      currentQuantity: currentQuantity ?? this.currentQuantity,
      unit: unit ?? this.unit,
      bufferThreshold: bufferThreshold ?? this.bufferThreshold,
      fdcId: fdcId ?? this.fdcId,
      lastAuditAt: lastAuditAt ?? this.lastAuditAt,
      sortOrder: sortOrder ?? this.sortOrder,
      createdBy: createdBy ?? this.createdBy,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
    );
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'household_id': householdId,
        'name': name,
        'category': category.dbValue,
        'current_quantity': currentQuantity,
        'unit': unit,
        if (bufferThreshold != null) 'buffer_threshold': bufferThreshold,
        if (fdcId != null) 'fdc_id': fdcId,
        if (lastAuditAt != null)
          'last_audit_at': lastAuditAt!.toUtc().toIso8601String(),
        'sort_order': sortOrder,
        if (createdBy != null) 'created_by': createdBy,
      };

  factory PantryItem.fromJson(Map<String, dynamic> json) => PantryItem(
        id: json['id'].toString(),
        householdId: json['household_id'].toString(),
        name: json['name']?.toString() ?? '',
        category: GroceryCategory.values.firstWhereOrNull(
              (c) => c.dbValue == json['category'],
            ) ??
            GroceryCategory.other,
        currentQuantity: (json['current_quantity'] as num?)?.toDouble() ?? 0,
        unit: json['unit']?.toString() ?? 'g',
        bufferThreshold: (json['buffer_threshold'] as num?)?.toDouble(),
        fdcId: (json['fdc_id'] as num?)?.toInt(),
        lastAuditAt: DateTime.tryParse(json['last_audit_at']?.toString() ?? ''),
        sortOrder: (json['sort_order'] as num?)?.toInt() ?? 0,
        createdBy: json['created_by']?.toString(),
        createdAt: DateTime.tryParse(json['created_at']?.toString() ?? ''),
        updatedAt: DateTime.tryParse(json['updated_at']?.toString() ?? ''),
      );
}
