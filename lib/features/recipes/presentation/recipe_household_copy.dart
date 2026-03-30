import 'package:collection/collection.dart';
import 'package:plateplan/core/models/app_models.dart';

/// Whether [personal] appears to have a linked household copy in [allRecipes].
bool hasLikelyHouseholdCopyForPersonal({
  required Recipe personal,
  required List<Recipe> allRecipes,
  required String currentUserId,
}) {
  return householdCopyRecipeForPersonal(
        personal: personal,
        allRecipes: allRecipes,
        currentUserId: currentUserId,
      ) !=
      null;
}

/// Household copy row for this personal recipe, if we can resolve it locally.
Recipe? householdCopyRecipeForPersonal({
  required Recipe personal,
  required List<Recipe> allRecipes,
  required String currentUserId,
}) {
  final byLink = allRecipes.firstWhereOrNull(
    (r) =>
        r.visibility == RecipeVisibility.household &&
        (r.copiedFromPersonalRecipeId ?? '') == personal.id &&
        (r.userId ?? '') == currentUserId,
  );
  if (byLink != null) return byLink;
  final t = personal.title.trim().toLowerCase();
  return allRecipes.firstWhereOrNull(
    (r) =>
        r.id != personal.id &&
        r.visibility == RecipeVisibility.household &&
        (r.userId ?? '') == currentUserId &&
        r.title.trim().toLowerCase() == t,
  );
}
