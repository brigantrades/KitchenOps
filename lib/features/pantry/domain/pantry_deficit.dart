import 'package:collection/collection.dart';
import 'package:plateplan/core/models/app_models.dart';
import 'package:plateplan/core/pantry/pantry_quantity_math.dart';

/// One pantry line that is short for the week, or needs manual review.
class PantryDeficit {
  const PantryDeficit({
    required this.ingredientDisplayName,
    required this.nameKey,
    required this.kind,
    required this.needed,
    required this.onHand,
    required this.shortfall,
    this.pantryItemId,
    this.needsReview = false,
    this.reviewReason,
  });

  final String ingredientDisplayName;
  final String nameKey;
  final PantryPhysicalKind kind;
  final NormalizedQuantity needed;
  final NormalizedQuantity? onHand;
  final NormalizedQuantity shortfall;
  final String? pantryItemId;
  final bool needsReview;
  final String? reviewReason;
}

/// Unmatched ingredient demand (no pantry row or incompatible units).
class UnmatchedRecipeNeed {
  const UnmatchedRecipeNeed({
    required this.ingredientDisplayName,
    required this.nameKey,
    required this.normalized,
    this.reason,
  });

  final String ingredientDisplayName;
  final String nameKey;
  final NormalizedQuantity normalized;
  final String? reason;
}

/// Aggregates scaled recipe demand for a week and compares to pantry stock.
class PantryDeficitCalculator {
  /// [slots] should be for a single week; [recipeById] must include every
  /// referenced recipe id.
  static PantryDeficitResult compute({
    required List<MealPlanSlot> slots,
    required Map<String, Recipe> recipeById,
    required List<PantryItem> pantryItems,
  }) {
    final demand = <String, DemandBucket>{};

    void addIngredientScaled(Ingredient ing, double scale) {
      if (ing.qualitative) return;
      final scaledAmount = ing.amount * scale;
      final n = normalizePantryAmount(
        scaledAmount,
        ing.unit,
        qualitative: false,
      );
      if (n == null) return;
      final key = demandMapKey(normalizeGroceryItemName(ing.name), n.kind);
      demand.putIfAbsent(
        key,
        () => DemandBucket(
          nameKey: normalizeGroceryItemName(ing.name),
          kind: n.kind,
          sampleDisplayName: ing.name.trim(),
        ),
      );
      demand[key]!.total += n.value;
    }

    for (final slot in slots) {
      final mainId = slot.recipeId?.trim();
      if (mainId != null && mainId.isNotEmpty) {
        final recipe = recipeById[mainId];
        if (recipe != null) {
          final scale = slot.servingsUsed / recipe.servings.clamp(1, 999999);
          for (final ing in recipe.ingredients) {
            addIngredientScaled(ing, scale);
          }
        }
      }
      final sideId = slot.sideRecipeId?.trim();
      if (sideId != null && sideId.isNotEmpty) {
        final recipe = recipeById[sideId];
        if (recipe != null) {
          final scale = slot.servingsUsed / recipe.servings.clamp(1, 999999);
          for (final ing in recipe.ingredients) {
            addIngredientScaled(ing, scale);
          }
        }
      }
      final sauceId = slot.sauceRecipeId?.trim();
      if (sauceId != null && sauceId.isNotEmpty) {
        final recipe = recipeById[sauceId];
        if (recipe != null) {
          final scale = slot.servingsUsed / recipe.servings.clamp(1, 999999);
          for (final ing in recipe.ingredients) {
            addIngredientScaled(ing, scale);
          }
        }
      }
      for (final side in slot.sideItems) {
        final rid = side.recipeId?.trim();
        if (rid == null || rid.isEmpty) continue;
        final recipe = recipeById[rid];
        if (recipe != null) {
          final scale = slot.servingsUsed / recipe.servings.clamp(1, 999999);
          for (final ing in recipe.ingredients) {
            addIngredientScaled(ing, scale);
          }
        }
      }
    }

    final pantryByKey = <String, PantryItem>{};
    for (final p in pantryItems) {
      final nk = normalizeGroceryItemName(p.name);
      final n = normalizePantryAmount(
        p.currentQuantity,
        p.unit,
        qualitative: false,
      );
      if (n == null) continue;
      final key = demandMapKey(nk, n.kind);
      pantryByKey[key] = p;
    }

    final deficits = <PantryDeficit>[];
    final unmatched = <UnmatchedRecipeNeed>[];

    for (final entry in demand.entries) {
      final bucket = entry.value;
      final kind = bucket.kind;
      final nameKey = bucket.nameKey;
      final key = demandMapKey(nameKey, kind);
      final need = NormalizedQuantity(
        kind: kind,
        value: bucket.total,
        displayUnit: kind == PantryPhysicalKind.mass
            ? 'g'
            : kind == PantryPhysicalKind.volume
                ? 'ml'
                : 'each',
      );

      final pantryRow = pantryByKey[key] ??
          pantryItems.firstWhereOrNull(
            (p) =>
                normalizeGroceryItemName(p.name) == nameKey &&
                normalizePantryAmount(
                      p.currentQuantity,
                      p.unit,
                      qualitative: false,
                    )?.kind ==
                    kind,
          );

      if (pantryRow == null) {
        unmatched.add(
          UnmatchedRecipeNeed(
            ingredientDisplayName: bucket.sampleDisplayName,
            nameKey: nameKey,
            normalized: need,
            reason: 'No pantry line for this ingredient',
          ),
        );
        continue;
      }

      final stock = normalizePantryAmount(
        pantryRow.currentQuantity,
        pantryRow.unit,
        qualitative: false,
      );
      if (stock == null || stock.kind != kind) {
        unmatched.add(
          UnmatchedRecipeNeed(
            ingredientDisplayName: bucket.sampleDisplayName,
            nameKey: nameKey,
            normalized: need,
            reason: 'Pantry units do not match recipe units',
          ),
        );
        continue;
      }

      final short = need.value - stock.value;
      if (short <= 0.0001) continue;

      deficits.add(
        PantryDeficit(
          ingredientDisplayName: bucket.sampleDisplayName,
          nameKey: nameKey,
          kind: kind,
          needed: need,
          onHand: stock,
          shortfall: NormalizedQuantity(
            kind: kind,
            value: short,
            displayUnit: stock.displayUnit,
          ),
          pantryItemId: pantryRow.id,
        ),
      );
    }

    return PantryDeficitResult(
      deficits: deficits,
      unmatchedNeeds: unmatched,
    );
  }
}

class DemandBucket {
  DemandBucket({
    required this.nameKey,
    required this.kind,
    required this.sampleDisplayName,
  });

  final String nameKey;
  final PantryPhysicalKind kind;
  final String sampleDisplayName;
  double total = 0;
}

class PantryDeficitResult {
  const PantryDeficitResult({
    required this.deficits,
    required this.unmatchedNeeds,
  });

  final List<PantryDeficit> deficits;
  final List<UnmatchedRecipeNeed> unmatchedNeeds;
}
