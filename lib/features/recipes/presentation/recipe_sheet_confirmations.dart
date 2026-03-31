import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:plateplan/core/models/app_models.dart';
import 'package:plateplan/features/auth/data/auth_providers.dart';
import 'package:plateplan/features/recipes/data/recipes_repository.dart';
import 'package:plateplan/features/recipes/presentation/recipe_household_copy.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

Future<void> confirmAndDeleteRecipe(
  BuildContext context,
  Recipe recipe,
) async {
  if (!context.mounted) return;
  final container = ProviderScope.containerOf(context, listen: false);
  final repo = container.read(recipesRepositoryProvider);
  final removesForHousehold = recipe.visibility == RecipeVisibility.household;
  final confirmed = await showDialog<bool>(
    context: context,
    builder: (dialogContext) {
      final scheme = Theme.of(dialogContext).colorScheme;
      return AlertDialog(
        title: const Text('Remove recipe permanently?'),
        content: Text(
          removesForHousehold
              ? 'This will permanently remove "${recipe.title}" '
                  'from Household Recipes for everyone in your household.'
              : 'This will permanently delete "${recipe.title}" '
                  'from your recipes only. If you shared a copy to '
                  'Household Recipes, that copy stays until you remove '
                  'it from the Household tab.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(true),
            style: TextButton.styleFrom(foregroundColor: scheme.error),
            child: const Text('Remove'),
          ),
        ],
      );
    },
  );
  if (confirmed != true) return;
  if (!context.mounted) return;
  try {
    await repo.deleteRecipe(recipe.id);
    if (!context.mounted) return;
    container.invalidate(recipesProvider);
    if (!context.mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          removesForHousehold
              ? '"${recipe.title}" removed for your household.'
              : '"${recipe.title}" deleted from your recipes.',
        ),
      ),
    );
  } on PostgrestException catch (error) {
    if (!context.mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text('Could not remove recipe: ${error.message}'),
      ),
    );
  } catch (error) {
    if (!context.mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('Could not remove recipe: $error')),
    );
  }
}

Future<void> confirmAndRemoveHouseholdCopyOnly(
  BuildContext context,
  Recipe personalRecipe,
) async {
  if (!context.mounted) return;
  final container = ProviderScope.containerOf(context, listen: false);

  final confirmed = await showDialog<bool>(
    context: context,
    builder: (dialogContext) {
      final scheme = Theme.of(dialogContext).colorScheme;
      return AlertDialog(
        title: const Text('Remove from household?'),
        content: Text(
          'Remove the shared household copy of "${personalRecipe.title}"? '
          'Everyone in your household will lose access to that copy. '
          'Your personal recipe stays in My Recipes.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(true),
            style: TextButton.styleFrom(foregroundColor: scheme.error),
            child: const Text('Remove'),
          ),
        ],
      );
    },
  );
  if (confirmed != true) return;
  if (!context.mounted) return;
  final user = container.read(currentUserProvider);
  if (user == null) return;
  try {
    final repo = container.read(recipesRepositoryProvider);
    final deleted = await repo.deleteHouseholdCopyMatchingPersonal(
      userId: user.id,
      personalRecipeId: personalRecipe.id,
    );
    if (!context.mounted) return;
    container.invalidate(recipesProvider);
    if (!context.mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          deleted
              ? 'Removed "${personalRecipe.title}" from Household Recipes.'
              : 'No matching household copy found. It may already be removed, or the title changed after sharing.',
        ),
      ),
    );
  } on PostgrestException catch (error) {
    if (!context.mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text('Could not remove household copy: ${error.message}'),
      ),
    );
  } catch (error) {
    if (!context.mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('Could not remove household copy: $error')),
    );
  }
}

Future<void> confirmAndDeleteRecipeWithOptions(
  BuildContext context, {
  required Recipe recipe,
  required List<Recipe> allRecipes,
}) async {
  if (!context.mounted) return;
  final container = ProviderScope.containerOf(context, listen: false);
  final repo = container.read(recipesRepositoryProvider);
  final user = container.read(currentUserProvider);

  final isHousehold = recipe.visibility == RecipeVisibility.household;
  final userId = user?.id ?? '';
  final hasHouseholdCopy = !isHousehold &&
      userId.isNotEmpty &&
      hasLikelyHouseholdCopyForPersonal(
        personal: recipe,
        allRecipes: allRecipes,
        currentUserId: userId,
      );

  var deletePersonal = !isHousehold;
  var deleteHousehold = isHousehold;

  final confirmed = await showDialog<bool>(
    context: context,
    builder: (dialogContext) {
      final scheme = Theme.of(dialogContext).colorScheme;
      return StatefulBuilder(
        builder: (context, setDialogState) {
          final nothingSelected = (!deletePersonal && !deleteHousehold);
          return AlertDialog(
            title: const Text('Delete recipe?'),
            content: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  '"${recipe.title}"',
                  style: Theme.of(context).textTheme.titleSmall?.copyWith(
                        fontWeight: FontWeight.w700,
                      ),
                ),
                const SizedBox(height: 12),
                if (isHousehold)
                  Text(
                    'This will remove the recipe for everyone in your household.',
                    style: Theme.of(context).textTheme.bodyMedium,
                  )
                else
                  Text(
                    hasHouseholdCopy
                        ? 'Choose what to delete.'
                        : 'This will delete the recipe from your recipes only.',
                    style: Theme.of(context).textTheme.bodyMedium,
                  ),
                const SizedBox(height: 10),
                if (!isHousehold)
                  CheckboxListTile(
                    contentPadding: EdgeInsets.zero,
                    value: deletePersonal,
                    onChanged: (v) => setDialogState(
                      () => deletePersonal = v ?? deletePersonal,
                    ),
                    title: const Text('Delete from My Recipes'),
                    subtitle: const Text('Removes it from your personal library.'),
                  ),
                if (!isHousehold && hasHouseholdCopy)
                  CheckboxListTile(
                    contentPadding: EdgeInsets.zero,
                    value: deleteHousehold,
                    onChanged: (v) => setDialogState(
                      () => deleteHousehold = v ?? deleteHousehold,
                    ),
                    title: const Text('Delete household copy'),
                    subtitle: const Text(
                      'Removes it from Household Recipes for everyone.',
                    ),
                  ),
                if (isHousehold)
                  CheckboxListTile(
                    contentPadding: EdgeInsets.zero,
                    value: deleteHousehold,
                    onChanged: (v) => setDialogState(
                      () => deleteHousehold = v ?? deleteHousehold,
                    ),
                    title: const Text('Delete for household'),
                    subtitle: const Text(
                      'Removes it from Household Recipes for everyone.',
                    ),
                  ),
                if (nothingSelected)
                  Padding(
                    padding: const EdgeInsets.only(top: 6),
                    child: Text(
                      'Select at least one option.',
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(
                            color: scheme.error,
                            fontWeight: FontWeight.w600,
                          ),
                    ),
                  ),
              ],
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.of(dialogContext).pop(false),
                child: const Text('Cancel'),
              ),
              TextButton(
                onPressed: nothingSelected
                    ? null
                    : () => Navigator.of(dialogContext).pop(true),
                style: TextButton.styleFrom(foregroundColor: scheme.error),
                child: const Text('Delete'),
              ),
            ],
          );
        },
      );
    },
  );

  if (confirmed != true) return;
  if (!context.mounted) return;

  if ((deleteHousehold && !isHousehold) && userId.isEmpty) {
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Sign in required.')),
    );
    return;
  }

  try {
    var didDeletePersonal = false;
    var didDeleteHousehold = false;

    if (deleteHousehold && isHousehold) {
      await repo.deleteRecipe(recipe.id);
      didDeleteHousehold = true;
    } else if (deleteHousehold && !isHousehold) {
      final deleted = await repo.deleteHouseholdCopyMatchingPersonal(
        userId: userId,
        personalRecipeId: recipe.id,
      );
      didDeleteHousehold = deleted;
    }

    if (deletePersonal && !isHousehold) {
      await repo.deleteRecipe(recipe.id);
      didDeletePersonal = true;
    }

    container.invalidate(recipesProvider);
    if (!context.mounted) return;

    final parts = <String>[];
    if (didDeletePersonal) parts.add('My Recipes');
    if (didDeleteHousehold) parts.add('Household Recipes');
    final msg = parts.isEmpty
        ? 'Nothing was deleted.'
        : 'Deleted from ${parts.join(' and ')}.';
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));
  } on PostgrestException catch (error) {
    if (!context.mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('Could not delete: ${error.message}')),
    );
  } catch (error) {
    if (!context.mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('Could not delete: $error')),
    );
  }
}
