import 'package:collection/collection.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:plateplan/core/models/app_models.dart';
import 'package:plateplan/features/auth/data/auth_providers.dart';
import 'package:plateplan/features/recipes/data/recipes_repository.dart';
import 'package:plateplan/features/recipes/presentation/recipe_household_copy.dart';
import 'package:plateplan/features/recipes/presentation/recipe_sheet_confirmations.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

void showRecipeListsSharingSheet({
  required BuildContext context,
  required BuildContext anchorContext,
  required String recipeId,
  required bool hasSharedHousehold,
}) {
  showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    showDragHandle: true,
    builder: (sheetContext) => RecipeListsSharingSheet(
      anchorContext: anchorContext,
      recipeId: recipeId,
      hasSharedHousehold: hasSharedHousehold,
    ),
  );
}

class RecipeListsSharingSheet extends ConsumerStatefulWidget {
  const RecipeListsSharingSheet({
    super.key,
    required this.anchorContext,
    required this.recipeId,
    required this.hasSharedHousehold,
  });

  final BuildContext anchorContext;
  final String recipeId;
  final bool hasSharedHousehold;

  @override
  ConsumerState<RecipeListsSharingSheet> createState() =>
      _RecipeListsSharingSheetState();
}

class _RecipeListsSharingSheetState
    extends ConsumerState<RecipeListsSharingSheet> {
  bool _sharing = false;
  bool _removingHouseholdCopy = false;
  String? _appliedHouseholdShareDefaultsForRecipeId;
  bool _householdFavoriteOnShare = false;
  bool _householdToTryOnShare = false;
  bool _householdShareEnabled = false;

  @override
  void didUpdateWidget(covariant RecipeListsSharingSheet oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.recipeId != widget.recipeId) {
      _householdShareEnabled = false;
      _appliedHouseholdShareDefaultsForRecipeId = null;
      _sharing = false;
      _removingHouseholdCopy = false;
    }
  }

  Future<void> _shareToHousehold(Recipe recipe) async {
    final user = ref.read(currentUserProvider);
    if (user == null) return;
    final favorite = _appliedHouseholdShareDefaultsForRecipeId == recipe.id
        ? _householdFavoriteOnShare
        : recipe.isFavorite;
    final toTry = _appliedHouseholdShareDefaultsForRecipeId == recipe.id
        ? _householdToTryOnShare
        : recipe.isToTry;
    setState(() => _sharing = true);
    try {
      await ref.read(recipesRepositoryProvider).copyPersonalRecipeToHousehold(
            userId: user.id,
            recipeId: recipe.id,
            householdFavorite: favorite,
            householdToTry: toTry,
          );
      ref.invalidate(recipesProvider);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Shared "${recipe.title}" to Household Recipes.'),
        ),
      );
    } on PostgrestException catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Could not share recipe: ${error.message}'),
        ),
      );
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Could not share recipe: $error')),
      );
    } finally {
      if (mounted) setState(() => _sharing = false);
    }
  }

  Future<void> _removeHouseholdCopyOnly(Recipe personalRecipe) async {
    if (_removingHouseholdCopy) return;
    setState(() => _removingHouseholdCopy = true);
    try {
      await confirmAndRemoveHouseholdCopyOnly(
        widget.anchorContext,
        personalRecipe,
      );
    } finally {
      if (mounted) setState(() => _removingHouseholdCopy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final bottom = MediaQuery.viewInsetsOf(context).bottom;
    final recipesAsync = ref.watch(recipesProvider);

    return recipesAsync.when(
      loading: () => Padding(
        padding: EdgeInsets.fromLTRB(24, 16, 24, 24 + bottom),
        child: const Center(child: CircularProgressIndicator()),
      ),
      error: (e, _) => Padding(
        padding: EdgeInsets.fromLTRB(24, 16, 24, 24 + bottom),
        child: Text('Could not load recipe: $e'),
      ),
      data: (recipes) {
        final recipe = recipes.firstWhereOrNull((r) => r.id == widget.recipeId);
        if (recipe == null) {
          WidgetsBinding.instance.addPostFrameCallback((_) {
            if (mounted) Navigator.of(context).pop();
          });
          return const SizedBox.shrink();
        }

        final canSharePersonal = widget.hasSharedHousehold &&
            recipe.visibility == RecipeVisibility.personal;
        final user = ref.watch(currentUserProvider);
        final hasLikelyHouseholdCopy = user != null &&
            recipe.visibility == RecipeVisibility.personal &&
            hasLikelyHouseholdCopyForPersonal(
              personal: recipe,
              allRecipes: recipes,
              currentUserId: user.id,
            );
        final householdCopy = user != null &&
                recipe.visibility == RecipeVisibility.personal
            ? householdCopyRecipeForPersonal(
                personal: recipe,
                allRecipes: recipes,
                currentUserId: user.id,
              )
            : null;
        final householdMasterOn =
            hasLikelyHouseholdCopy || _householdShareEnabled;

        return SingleChildScrollView(
          padding: EdgeInsets.fromLTRB(8, 0, 8, 16 + bottom),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 4, 16, 4),
                child: Text(
                  'Lists & Sharing',
                  style: Theme.of(context).textTheme.titleLarge?.copyWith(
                        fontWeight: FontWeight.w800,
                      ),
                ),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
                child: Text(
                  'Turn each option on or off to choose where "${recipe.title}" '
                  'shows up. The recipe stays saved until you remove it permanently below.',
                  style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                        color: scheme.onSurfaceVariant,
                      ),
                ),
              ),
              if (recipe.visibility == RecipeVisibility.household) ...[
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 8, 16, 4),
                  child: Text(
                    'Household',
                    style: Theme.of(context).textTheme.titleSmall?.copyWith(
                          fontWeight: FontWeight.w700,
                        ),
                  ),
                ),
                ListTile(
                  leading: Icon(Icons.home_outlined, color: scheme.primary),
                  title: const Text('Shared copy'),
                  subtitle: const Text(
                    'Everyone in your household can open and cook from this row.',
                  ),
                ),
                SwitchListTile(
                  secondary:
                      Icon(Icons.favorite_outline, color: scheme.outline),
                  title: const Text('Favorite on Household Recipes'),
                  subtitle: const Text(
                    'When on, this recipe appears under Favorites on Household Recipes.',
                  ),
                  value: recipe.isFavorite,
                  onChanged: (v) async {
                    await ref.read(recipesRepositoryProvider).toggleFavorite(
                          recipe.id,
                          v,
                        );
                    ref.invalidate(recipesProvider);
                  },
                ),
                SwitchListTile(
                  secondary:
                      Icon(Icons.bookmark_outline, color: scheme.outline),
                  title: const Text('To Try on Household Recipes'),
                  subtitle: const Text(
                    'Used in Planner and Discover for this household copy.',
                  ),
                  value: recipe.isToTry,
                  onChanged: (v) async {
                    await ref.read(recipesRepositoryProvider).toggleToTry(
                          recipe.id,
                          v,
                        );
                    ref.invalidate(recipesProvider);
                  },
                ),
              ] else ...[
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 8, 16, 4),
                  child: Text(
                    'My Recipes',
                    style: Theme.of(context).textTheme.titleSmall?.copyWith(
                          fontWeight: FontWeight.w700,
                        ),
                  ),
                ),
                SwitchListTile(
                  secondary:
                      Icon(Icons.favorite_outline, color: scheme.outline),
                  title: const Text('Favorite'),
                  subtitle: const Text(
                    'Show under Favorites on My Recipes only.',
                  ),
                  value: recipe.isFavorite,
                  onChanged: (v) async {
                    await ref.read(recipesRepositoryProvider).toggleFavorite(
                          recipe.id,
                          v,
                        );
                    ref.invalidate(recipesProvider);
                  },
                ),
                SwitchListTile(
                  secondary:
                      Icon(Icons.bookmark_outline, color: scheme.outline),
                  title: const Text('To Try'),
                  subtitle: const Text(
                    'Show under To Try on My Recipes only.',
                  ),
                  value: recipe.isToTry,
                  onChanged: (v) async {
                    await ref.read(recipesRepositoryProvider).toggleToTry(
                          recipe.id,
                          v,
                        );
                    ref.invalidate(recipesProvider);
                  },
                ),
                const Divider(height: 1),
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
                  child: Text(
                    'Household',
                    style: Theme.of(context).textTheme.titleSmall?.copyWith(
                          fontWeight: FontWeight.w700,
                        ),
                  ),
                ),
                if (!canSharePersonal)
                  ListTile(
                    leading: Icon(Icons.home_outlined, color: scheme.primary),
                    title: const Text('Share with household'),
                    subtitle: const Text(
                      'Create or join a household in Settings to share recipes.',
                    ),
                  )
                else ...[
                  SwitchListTile(
                    secondary: Icon(
                      Icons.groups_2_outlined,
                      color: householdMasterOn
                          ? scheme.primary
                          : scheme.onSurfaceVariant,
                    ),
                    title: Text(
                      hasLikelyHouseholdCopy
                          ? 'On Household Recipes'
                          : 'Share with household',
                    ),
                    subtitle: Text(
                      hasLikelyHouseholdCopy
                          ? 'Turn off to remove the shared copy (your personal recipe stays). '
                              'Favorite and To Try below apply to the household copy.'
                          : 'When on, choose how the shared copy appears, then tap Share.',
                    ),
                    value: householdMasterOn,
                    onChanged: _removingHouseholdCopy
                        ? null
                        : (v) async {
                            if (hasLikelyHouseholdCopy) {
                              if (!v) {
                                await _removeHouseholdCopyOnly(recipe);
                              }
                              return;
                            }
                            setState(() {
                              _householdShareEnabled = v;
                              if (v) {
                                _appliedHouseholdShareDefaultsForRecipeId =
                                    recipe.id;
                                _householdFavoriteOnShare = recipe.isFavorite;
                                _householdToTryOnShare = recipe.isToTry;
                              } else {
                                _appliedHouseholdShareDefaultsForRecipeId =
                                    null;
                                _householdFavoriteOnShare = false;
                                _householdToTryOnShare = false;
                              }
                            });
                          },
                  ),
                  if (_householdShareEnabled && !hasLikelyHouseholdCopy) ...[
                    SwitchListTile(
                      secondary: Icon(
                        Icons.favorite_outline,
                        color: scheme.outline,
                      ),
                      title: const Text('Favorite on Household Recipes'),
                      subtitle: const Text(
                        'Applies to the shared copy after you tap Share.',
                      ),
                      value:
                          _appliedHouseholdShareDefaultsForRecipeId == recipe.id
                              ? _householdFavoriteOnShare
                              : recipe.isFavorite,
                      onChanged: (v) => setState(() {
                        _appliedHouseholdShareDefaultsForRecipeId = recipe.id;
                        _householdFavoriteOnShare = v;
                      }),
                    ),
                    SwitchListTile(
                      secondary: Icon(
                        Icons.bookmark_outline,
                        color: scheme.outline,
                      ),
                      title: const Text('To Try on Household Recipes'),
                      subtitle: const Text(
                        'Applies to the shared copy after you tap Share.',
                      ),
                      value:
                          _appliedHouseholdShareDefaultsForRecipeId == recipe.id
                              ? _householdToTryOnShare
                              : recipe.isToTry,
                      onChanged: (v) => setState(() {
                        _appliedHouseholdShareDefaultsForRecipeId = recipe.id;
                        _householdToTryOnShare = v;
                      }),
                    ),
                    Padding(
                      padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
                      child: Align(
                        alignment: Alignment.centerRight,
                        child: _sharing
                            ? const SizedBox(
                                width: 28,
                                height: 28,
                                child:
                                    CircularProgressIndicator(strokeWidth: 2),
                              )
                            : FilledButton.tonal(
                                onPressed: () => _shareToHousehold(recipe),
                                child: const Text('Share'),
                              ),
                      ),
                    ),
                  ],
                  if (hasLikelyHouseholdCopy && householdCopy != null) ...[
                    SwitchListTile(
                      secondary: Icon(
                        Icons.favorite_outline,
                        color: scheme.outline,
                      ),
                      title: const Text('Favorite on Household Recipes'),
                      subtitle: const Text(
                        'Updates the shared household copy.',
                      ),
                      value: householdCopy.isFavorite,
                      onChanged: (v) async {
                        await ref.read(recipesRepositoryProvider).toggleFavorite(
                              householdCopy.id,
                              v,
                            );
                        ref.invalidate(recipesProvider);
                      },
                    ),
                    SwitchListTile(
                      secondary: Icon(
                        Icons.bookmark_outline,
                        color: scheme.outline,
                      ),
                      title: const Text('To Try on Household Recipes'),
                      subtitle: const Text(
                        'Updates the shared household copy.',
                      ),
                      value: householdCopy.isToTry,
                      onChanged: (v) async {
                        await ref.read(recipesRepositoryProvider).toggleToTry(
                              householdCopy.id,
                              v,
                            );
                        ref.invalidate(recipesProvider);
                      },
                    ),
                  ],
                ],
              ],
              const SizedBox(height: 8),
              const Divider(height: 1),
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
                child: Text(
                  recipe.visibility == RecipeVisibility.household
                      ? 'Remove from household'
                      : 'Delete recipe',
                  style: Theme.of(context).textTheme.titleSmall?.copyWith(
                        fontWeight: FontWeight.w700,
                        color: scheme.onSurfaceVariant,
                      ),
                ),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 0, 16, 4),
                child: Text(
                  recipe.visibility == RecipeVisibility.household
                      ? 'This removes the shared recipe for every household member.'
                      : 'This deletes only this recipe row (your personal copy).',
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        color: scheme.onSurfaceVariant,
                      ),
                ),
              ),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 8),
                child: TextButton(
                  onPressed: () async {
                    Navigator.of(context).pop();
                    await Future<void>.delayed(Duration.zero);
                    if (!widget.anchorContext.mounted) return;
                    await confirmAndDeleteRecipe(
                      widget.anchorContext,
                      recipe,
                    );
                  },
                  child: Text(
                    recipe.visibility == RecipeVisibility.household
                        ? 'Remove for everyone…'
                        : 'Delete my recipe permanently…',
                    style: TextStyle(color: scheme.error),
                  ),
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}
