import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:plateplan/core/models/app_models.dart';
import 'package:plateplan/features/auth/data/auth_providers.dart';
import 'package:plateplan/features/recipes/data/recipes_repository.dart';
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
