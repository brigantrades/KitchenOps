import 'package:collection/collection.dart';

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

enum HouseholdRole { owner, member }

enum HouseholdMemberStatus { active, invited }

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
  });

  final String name;
  final double amount;
  final String unit;
  final GroceryCategory category;

  Map<String, dynamic> toJson() => {
        'name': name,
        'amount': amount,
        'unit': unit,
        'category': category.dbValue,
      };

  factory Ingredient.fromJson(Map<String, dynamic> json) => Ingredient(
        name: json['name']?.toString() ?? '',
        amount: (json['amount'] as num?)?.toDouble() ?? 0,
        unit: json['unit']?.toString() ?? '',
        category: GroceryCategory.values.firstWhereOrNull(
              (c) => c.dbValue == json['category'],
            ) ??
            GroceryCategory.other,
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
    this.userId,
    this.householdId,
    this.visibility = RecipeVisibility.personal,
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
  final String? userId;
  final String? householdId;
  final RecipeVisibility visibility;

  Recipe copyWith({
    bool? isFavorite,
    bool? isToTry,
    int? servings,
    String? householdId,
    RecipeVisibility? visibility,
  }) =>
      Recipe(
        id: id,
        title: title,
        description: description,
        servings: servings ?? this.servings,
        prepTime: prepTime,
        cookTime: cookTime,
        mealType: mealType,
        cuisineTags: cuisineTags,
        ingredients: ingredients,
        instructions: instructions,
        imageUrl: imageUrl,
        nutrition: nutrition,
        isFavorite: isFavorite ?? this.isFavorite,
        isToTry: isToTry ?? this.isToTry,
        source: source,
        userId: userId,
        householdId: householdId ?? this.householdId,
        visibility: visibility ?? this.visibility,
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
        'user_id': userId,
        'household_id': householdId,
        'visibility': visibility.name,
      };

  factory Recipe.fromJson(Map<String, dynamic> json) => Recipe(
        id: json['id'].toString(),
        title: json['title']?.toString() ?? '',
        description: json['description']?.toString(),
        servings: (json['servings'] as num?)?.toInt() ?? 2,
        prepTime: (json['prep_time'] as num?)?.toInt(),
        cookTime: (json['cook_time'] as num?)?.toInt(),
        mealType: _mealTypeFromDb(json['meal_type']?.toString()),
        cuisineTags: (json['cuisine_tags'] as List?)
                ?.map((e) => e.toString())
                .toList() ??
            const [],
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
        userId: json['user_id']?.toString(),
        householdId: json['household_id']?.toString(),
        visibility: RecipeVisibility.values.firstWhereOrNull(
              (v) => v.name == json['visibility'],
            ) ??
            RecipeVisibility.personal,
      );
}

class MealPlanSlot {
  const MealPlanSlot({
    required this.id,
    required this.weekStart,
    required this.dayOfWeek,
    required this.mealLabel,
    this.recipeId,
    this.mealText,
    this.sauceRecipeId,
    this.sauceText,
    this.servingsUsed = 1,
    this.slotOrder = 0,
  });

  final String id;
  final DateTime weekStart;
  final int dayOfWeek;
  final String mealLabel;
  final String? recipeId;
  final String? mealText;
  final String? sauceRecipeId;
  final String? sauceText;
  final int servingsUsed;
  final int slotOrder;

  bool get hasPlannedContent {
    final hasMealText = (mealText ?? '').trim().isNotEmpty;
    final hasSauceText = (sauceText ?? '').trim().isNotEmpty;
    return recipeId != null ||
        hasMealText ||
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
        'sauce_recipe_id': sauceRecipeId,
        'sauce_text': sauceText,
        'servings_used': servingsUsed,
        'slot_order': slotOrder,
      };

  factory MealPlanSlot.fromJson(Map<String, dynamic> json) => MealPlanSlot(
        id: json['id'].toString(),
        weekStart: DateTime.parse(json['week_start'].toString()),
        dayOfWeek: (json['day_of_week'] as num).toInt(),
        mealLabel: json['meal_type']?.toString() ?? 'meal',
        recipeId: json['recipe_id']?.toString(),
        mealText: json['meal_text']?.toString(),
        sauceRecipeId: json['sauce_recipe_id']?.toString(),
        sauceText: json['sauce_text']?.toString(),
        servingsUsed: (json['servings_used'] as num?)?.toInt() ?? 1,
        slotOrder: (json['slot_order'] as num?)?.toInt() ?? 0,
      );
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

  bool get fromPlanner => fromRecipeId != null;

  Map<String, dynamic> toJson() => {
        'id': id,
        'name': name,
        'category': category.dbValue,
        'quantity': quantity,
        'unit': unit,
        'from_recipe_id': fromRecipeId,
        'list_id': listId,
        'source_slot_id': sourceSlotId,
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
      );
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
        groceryListOrder:
            GroceryListOrder.fromJson(json['grocery_list_order']),
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
  });

  final String id;
  final String name;
  final String createdBy;

  factory Household.fromJson(Map<String, dynamic> json) => Household(
        id: json['id'].toString(),
        name: json['name']?.toString() ?? 'My Household',
        createdBy: json['created_by']?.toString() ?? '',
      );
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

  factory HouseholdMember.fromJson(Map<String, dynamic> json) {
    final profile = json['profiles'] as Map<String, dynamic>?;
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
  });

  final String householdId;
  final String householdName;
  final HouseholdRole role;
  final String? invitedEmail;

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
    );
  }
}
