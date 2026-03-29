import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:plateplan/core/measurement/ingredient_display_units.dart';
import 'package:plateplan/core/measurement/measurement_system_provider.dart';
import 'package:plateplan/core/models/app_models.dart';
import 'package:plateplan/core/theme/app_brand.dart';
import 'package:plateplan/core/theme/design_tokens.dart';
import 'package:plateplan/core/ui/measurement_system_toggle.dart';
import 'package:plateplan/core/ui/recipo_kit.dart';
import 'package:plateplan/core/ui/section_card.dart';
import 'package:plateplan/features/auth/data/auth_providers.dart';
import 'package:plateplan/features/discover/data/discover_repository.dart';
import 'package:plateplan/features/grocery/data/grocery_repository.dart';
import 'package:plateplan/features/household/data/household_providers.dart';
import 'package:plateplan/features/planner/data/planner_repository.dart';
import 'package:plateplan/features/profile/data/profile_providers.dart';
import 'package:plateplan/features/recipes/data/recipes_repository.dart';

class DiscoverScreen extends ConsumerStatefulWidget {
  const DiscoverScreen({super.key});

  @override
  ConsumerState<DiscoverScreen> createState() => _DiscoverScreenState();
}

class _DiscoverScreenState extends ConsumerState<DiscoverScreen> {
  late final TextEditingController _searchController;

  @override
  void initState() {
    super.initState();
    _searchController = TextEditingController(
      text: ref.read(discoverSearchQueryProvider),
    );
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final selectedMeal = ref.watch(discoverMealTypeProvider);
    final isBreakfastOnlySelected = selectedMeal == DiscoverMealType.entree;
    final isLunchOnlySelected = selectedMeal == DiscoverMealType.side;
    final isSnackOnlySelected = selectedMeal == DiscoverMealType.snack;
    final isDessertOnlySelected = selectedMeal == DiscoverMealType.dessert;
    final featuredRecipesAsync = isBreakfastOnlySelected
        ? ref.watch(discoverLazyBreakfastRecipesProvider)
        : isLunchOnlySelected
            ? ref.watch(discoverQuickLunchRecipesProvider)
            : isSnackOnlySelected
                ? ref.watch(discoverSnackIdeasRecipesProvider)
                : isDessertOnlySelected
                    ? ref.watch(discoverDessertIdeasRecipesProvider)
                    : ref.watch(discoverQuickEasyRecipesProvider);
    final featuredSectionTitle = isBreakfastOnlySelected
        ? 'Lazy Breakfast Ideas'
        : isLunchOnlySelected
            ? 'Quick & Easy Lunch Ideas'
            : isSnackOnlySelected
                ? 'Snack Ideas'
                : isDessertOnlySelected
                    ? 'Dessert Ideas'
                    : 'Quick & Easy Dinners';
    final cuisinesAsync = ref.watch(discoverCuisineTilesProvider);

    return Scaffold(
      body: DecoratedBox(
        decoration: const BoxDecoration(
          color: AppBrand.paleMint,
        ),
        child: SafeArea(
          child: Column(
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(12, 8, 12, 0),
                child: Column(
                  children: [
                    _buildHeader(context),
                    const SizedBox(height: AppSpacing.sm),
                    _buildSearchOnly(),
                    const SizedBox(height: AppSpacing.sm),
                    _buildMealTypeChips(selectedMeal),
                    const SizedBox(height: AppSpacing.md),
                  ],
                ),
              ),
              Expanded(
                child: ListView(
                  padding: const EdgeInsets.fromLTRB(12, 0, 12, 16),
                  children: [
                    Container(
                      padding: const EdgeInsets.fromLTRB(12, 12, 12, 10),
                      decoration: const BoxDecoration(
                        color: AppBrand.offWhite,
                        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          _sectionTitle(context, featuredSectionTitle),
                          const SizedBox(height: AppSpacing.xs),
                          _buildQuickDinnerGrid(featuredRecipesAsync),
                          const SizedBox(height: AppSpacing.md),
                          // New From Users intentionally hidden for now.
                          _sectionTitle(context, 'Explore Cuisines'),
                          const SizedBox(height: AppSpacing.xs),
                          _buildCuisineGrid(cuisinesAsync),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildHeader(BuildContext context) {
    return Row(
      children: [
        const Spacer(),
        Text(
          'Discover',
          style: Theme.of(context).textTheme.titleLarge?.copyWith(
                fontWeight: FontWeight.w600,
              ),
        ),
        const Spacer(),
        InkWell(
          onTap: () => context.push('/profile'),
          borderRadius: BorderRadius.circular(14),
          child: const CircleAvatar(
            radius: 12,
            backgroundColor: AppBrand.mutedAqua,
            child: Icon(Icons.person_rounded, size: 14, color: AppBrand.deepTeal),
          ),
        ),
        const SizedBox(width: 8),
        InkWell(
          onTap: _showNotificationsDropdown,
          borderRadius: BorderRadius.circular(14),
          child: const Icon(
            Icons.notifications_none_rounded,
            size: 18,
            color: AppBrand.deepTeal,
          ),
        ),
      ],
    );
  }

  Widget _buildSearchOnly() {
    return TextField(
      controller: _searchController,
      onChanged: (value) {
        ref.read(discoverSearchQueryProvider.notifier).state = value;
      },
      decoration: const InputDecoration(
        prefixIcon: Icon(Icons.search_rounded),
        hintText: 'Search recipes',
        isDense: true,
      ),
    );
  }

  Widget _buildMealTypeChips(DiscoverMealType selectedMeal) {
    final meals = DiscoverMealType.values;
    final textTheme = Theme.of(context).textTheme;
    final colorScheme = Theme.of(context).colorScheme;

    return Wrap(
      spacing: 8,
      runSpacing: 8,
      children: meals.map((meal) {
        final isSelected = meal == selectedMeal;
        return InkWell(
          borderRadius: BorderRadius.circular(24),
          onTap: () {
            ref.read(discoverMealTypeProvider.notifier).state = meal;
            ref.read(discoverSelectedMealTypesProvider.notifier).state =
                <DiscoverMealType>{meal};
          },
          child: AnimatedContainer(
            duration: AppMotion.fast,
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
            decoration: BoxDecoration(
              color: isSelected ? colorScheme.secondary : AppBrand.offWhite,
              borderRadius: BorderRadius.circular(24),
              border: Border.all(
                color: isSelected
                    ? colorScheme.secondary
                    : AppBrand.mutedAqua,
              ),
            ),
            child: Text(
              meal.label,
              style: textTheme.labelLarge?.copyWith(
                fontWeight: FontWeight.w700,
                color: isSelected
                    ? colorScheme.onSecondary
                    : AppBrand.black,
              ),
            ),
          ),
        );
      }).toList(),
    );
  }

  Widget _sectionTitle(BuildContext context, String title) {
    return Text(
      title,
      style: Theme.of(context).textTheme.titleMedium?.copyWith(
            fontWeight: FontWeight.w700,
          ),
    );
  }

  Widget _buildTrendingStrip(AsyncValue<List<Recipe>> trendingAsync) {
    return trendingAsync.when(
      data: (recipes) => SizedBox(
        height: 52,
        child: ListView.separated(
          scrollDirection: Axis.horizontal,
          itemBuilder: (context, index) {
            final recipe = recipes[index];
            return GestureDetector(
              onTap: () => _showPublicRecipeDetail(recipe),
              child: CircleAvatar(
                radius: 24,
                backgroundImage: NetworkImage(_fallbackFoodImage(index)),
                backgroundColor:
                    Theme.of(context).colorScheme.primaryContainer,
                onBackgroundImageError: (_, __) {},
                child: ClipOval(
                  child: FoodMedia(
                    imageUrl: recipe.imageUrl?.isNotEmpty == true
                        ? recipe.imageUrl
                        : _fallbackFoodImage(index),
                    width: 48,
                    height: 48,
                  ),
                ),
              ),
            );
          },
          separatorBuilder: (_, __) => const SizedBox(width: 8),
          itemCount: recipes.length.clamp(0, 8),
        ),
      ),
      loading: () => const SizedBox(
        height: 52,
        child: Center(child: CircularProgressIndicator()),
      ),
      error: (_, __) => const SizedBox.shrink(),
    );
  }

  Widget _buildQuickDinnerGrid(AsyncValue<List<Recipe>> recipesAsync) {
    final savedRecipes = ref.watch(recipesProvider).valueOrNull ?? const <Recipe>[];
    return recipesAsync.when(
      data: (recipes) {
        final quickRecipes = recipes.take(8).toList();
        if (quickRecipes.isEmpty) return const SizedBox.shrink();
        return SizedBox(
          height: 212,
          child: ListView.separated(
            scrollDirection: Axis.horizontal,
            itemCount: quickRecipes.length,
            separatorBuilder: (_, __) => const SizedBox(width: 10),
            itemBuilder: (context, index) {
              final recipe = quickRecipes[index];
              final isSaved = _isRecipeSaved(recipe, savedRecipes);
              final imageUrl = recipe.imageUrl?.isNotEmpty == true
                  ? _normalizeImageUrl(recipe.imageUrl!) ?? recipe.imageUrl!
                  : _fallbackFoodImage(index + 10);
              return GestureDetector(
                onTap: () => _showPublicRecipeDetail(recipe),
                child: SizedBox(
                  width: 180,
                  child: Container(
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(12),
                      boxShadow: AppShadows.soft,
                      image: DecorationImage(
                        image: NetworkImage(imageUrl),
                        fit: BoxFit.cover,
                      ),
                    ),
                    child: Container(
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(12),
                        gradient: LinearGradient(
                          begin: Alignment.topCenter,
                          end: Alignment.bottomCenter,
                          colors: [
                            Colors.black.withValues(alpha: 0.08),
                            Colors.black.withValues(alpha: 0.65),
                          ],
                        ),
                      ),
                      padding: const EdgeInsets.all(8),
                      child: Column(
                        children: [
                          Row(
                            children: [
                              const Spacer(),
                              Container(
                                padding: const EdgeInsets.all(6),
                                decoration: BoxDecoration(
                                  color: const Color(0xFFC8D3C2)
                                      .withValues(alpha: 0.9),
                                  borderRadius: BorderRadius.circular(10),
                                ),
                                child: InkWell(
                                  onTap: () => _showSaveDestinationModal(recipe),
                                  borderRadius: BorderRadius.circular(10),
                                  child: Icon(
                                    isSaved
                                        ? Icons.bookmark_rounded
                                        : Icons.bookmark_border_rounded,
                                    size: 18,
                                    color: isSaved
                                        ? const Color(0xFF2F6B46)
                                        : const Color(0xFF2D342F),
                                  ),
                                ),
                              ),
                            ],
                          ),
                          const Spacer(),
                          Align(
                            alignment: Alignment.bottomLeft,
                            child: Text(
                              recipe.title.toUpperCase(),
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(
                                color: Colors.white,
                                fontWeight: FontWeight.w800,
                                fontSize: 14,
                                height: 1.05,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              );
            },
          ),
        );
      },
      loading: () => const SizedBox(
        height: 220,
        child: Center(child: CircularProgressIndicator()),
      ),
      error: (_, __) => const SizedBox.shrink(),
    );
  }

  Widget _buildNewFromUsers(AsyncValue<List<Recipe>> trendingAsync) {
    return trendingAsync.when(
      data: (recipes) {
        final count = recipes.isEmpty ? 4 : recipes.length.clamp(4, 8);
        return SizedBox(
          height: 42,
          child: ListView.separated(
            scrollDirection: Axis.horizontal,
            itemCount: count,
            separatorBuilder: (_, __) => const SizedBox(width: 10),
            itemBuilder: (context, index) => const CircleAvatar(
              radius: 18,
              backgroundColor: Color(0xFFE8ECEB),
              child: Icon(Icons.person_rounded,
                  color: Color(0xFF5F6A68), size: 18),
            ),
          ),
        );
      },
      loading: () => const SizedBox(
        height: 42,
        child: Center(child: CircularProgressIndicator()),
      ),
      error: (_, __) => const SizedBox.shrink(),
    );
  }

  Widget _buildCuisineGrid(
      AsyncValue<List<DiscoverCuisineTile>> cuisinesAsync) {
    final colors = <Color>[
      const Color(0xFFB7D0BC),
      const Color(0xFFF9B77D),
      const Color(0xFFC7B7E8),
      const Color(0xFFFFD06E),
      const Color(0xFF9ED5B5),
      const Color(0xFFF2C1B7),
    ];
    final icons = <IconData>[
      Icons.ramen_dining_rounded,
      Icons.local_dining_rounded,
      Icons.rice_bowl_rounded,
      Icons.emoji_food_beverage_rounded,
      Icons.set_meal_rounded,
      Icons.breakfast_dining_rounded,
    ];

    return cuisinesAsync.when(
      data: (tiles) => GridView.builder(
        shrinkWrap: true,
        physics: const NeverScrollableScrollPhysics(),
        itemCount: tiles.length,
        gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
          crossAxisCount: 2,
          mainAxisSpacing: 10,
          crossAxisSpacing: 10,
          childAspectRatio: 1.22,
        ),
        itemBuilder: (context, index) {
          final tile = tiles[index];
          return DiscoverCuisineCard(
            title: tile.label,
            subtitle: '${tile.recipeCount} recipes',
            color: colors[index % colors.length],
            icon: icons[index % icons.length],
            graphicUrl: _cuisineGraphicForLabel(tile.label),
            onTap: () {
              Navigator.of(context).push(
                MaterialPageRoute<void>(
                  builder: (_) => _DiscoverCuisineRecipesPage(
                    cuisineId: tile.id,
                    title: tile.label,
                    onOpenRecipe: _showPublicRecipeDetail,
                    onSaveRecipe: _showSaveDestinationModal,
                    onShowNotifications: _showNotificationsDropdown,
                  ),
                ),
              );
            },
          );
        },
      ),
      loading: () => const SizedBox(
        height: 120,
        child: Center(child: CircularProgressIndicator()),
      ),
      error: (_, __) => const SizedBox.shrink(),
    );
  }

  Future<void> _showPublicRecipeDetail(Recipe recipe) async {
    await Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => _DiscoverRecipeDetailPage(recipe: recipe),
      ),
    );
  }

  Future<void> _showNotificationsDropdown() async {
    String? actioningHouseholdId;
    var isAccepting = false;
    await showDialog<void>(
      context: context,
      barrierColor: Colors.black.withValues(alpha: 0.12),
      builder: (context) => StatefulBuilder(
        builder: (context, setModalState) => Consumer(
          builder: (context, ref, _) {
            final invitesAsync = ref.watch(pendingHouseholdInvitesProvider);

            Future<void> rejectInvite(HouseholdInvite invite) async {
              setModalState(() {
                actioningHouseholdId = invite.householdId;
                isAccepting = false;
              });
              try {
                await ref
                    .read(householdRepositoryProvider)
                    .rejectInvite(invite.householdId);
                ref.invalidate(pendingHouseholdInvitesProvider);
                ref.invalidate(householdMembersProvider);
                if (!mounted) return;
                ScaffoldMessenger.of(this.context).showSnackBar(
                  const SnackBar(content: Text('Invite declined.')),
                );
              } catch (error) {
                if (!mounted) return;
                ScaffoldMessenger.of(this.context).showSnackBar(
                  SnackBar(content: Text('Could not decline invite: $error')),
                );
              } finally {
                if (mounted) {
                  setModalState(() {
                    actioningHouseholdId = null;
                  });
                }
              }
            }

            Future<void> acceptInvite(HouseholdInvite invite) async {
              setModalState(() {
                actioningHouseholdId = invite.householdId;
                isAccepting = true;
              });
              try {
                await ref
                    .read(householdRepositoryProvider)
                    .acceptInvite(invite.householdId);
                ref.invalidate(profileProvider);
                ref.invalidate(activeHouseholdProvider);
                ref.invalidate(activeHouseholdIdProvider);
                ref.invalidate(householdMembersProvider);
                ref.invalidate(pendingHouseholdInvitesProvider);
                ref.invalidate(plannerSlotsProvider);
                invalidateActiveGroceryStreams(ref);
                ref.invalidate(listsProvider);
                ref.invalidate(recipesProvider);
                if (!mounted) return;
                ScaffoldMessenger.of(this.context).showSnackBar(
                  const SnackBar(content: Text('Joined household.')),
                );
              } catch (error) {
                if (!mounted) return;
                ScaffoldMessenger.of(this.context).showSnackBar(
                  SnackBar(content: Text('Could not accept invite: $error')),
                );
              } finally {
                if (mounted) {
                  setModalState(() {
                    actioningHouseholdId = null;
                    isAccepting = false;
                  });
                }
              }
            }

            return SafeArea(
              child: Align(
                alignment: Alignment.topRight,
                child: Container(
                  width: 360,
                  margin: const EdgeInsets.only(top: 56, right: 12, left: 12),
                  constraints: const BoxConstraints(maxHeight: 460),
                  padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
                  decoration: BoxDecoration(
                    color: AppBrand.offWhite,
                    borderRadius: BorderRadius.circular(14),
                    boxShadow: AppShadows.soft,
                  ),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Notifications',
                        style: Theme.of(context).textTheme.titleMedium?.copyWith(
                              fontWeight: FontWeight.w700,
                            ),
                      ),
                      const SizedBox(height: 10),
                      invitesAsync.when(
                        loading: () => const Padding(
                          padding: EdgeInsets.symmetric(vertical: 16),
                          child: Center(child: CircularProgressIndicator()),
                        ),
                        error: (error, _) => Padding(
                          padding: const EdgeInsets.symmetric(vertical: 12),
                          child: Text('Could not load notifications: $error'),
                        ),
                        data: (invites) {
                          if (invites.isEmpty) {
                            return const Padding(
                              padding: EdgeInsets.symmetric(vertical: 12),
                              child: Text('No notifications yet.'),
                            );
                          }
                          return Flexible(
                            child: ListView.separated(
                              shrinkWrap: true,
                              itemCount: invites.length,
                              separatorBuilder: (_, __) =>
                                  const SizedBox(height: 10),
                              itemBuilder: (context, index) {
                                final invite = invites[index];
                                final isBusy =
                                    actioningHouseholdId == invite.householdId;
                                return Container(
                                  padding: const EdgeInsets.all(10),
                                  decoration: BoxDecoration(
                                    color: Colors.white,
                                    borderRadius: BorderRadius.circular(12),
                                    boxShadow: AppShadows.soft,
                                  ),
                                  child: Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      Text(
                                        'Household invite: ${invite.householdName}',
                                        style: Theme.of(context)
                                            .textTheme
                                            .titleSmall
                                            ?.copyWith(
                                              fontWeight: FontWeight.w700,
                                            ),
                                      ),
                                      const SizedBox(height: 2),
                                      Text(
                                        [
                                          if (invite.invitedByEmail != null)
                                            'From ${invite.invitedByEmail}',
                                          'Role: ${invite.role.name}',
                                        ].join('  •  '),
                                        style: Theme.of(context)
                                            .textTheme
                                            .bodySmall,
                                      ),
                                      const SizedBox(height: 8),
                                      Row(
                                        children: [
                                          Expanded(
                                            child: OutlinedButton(
                                              onPressed: isBusy
                                                  ? null
                                                  : () => rejectInvite(invite),
                                              child: isBusy && !isAccepting
                                                  ? const SizedBox(
                                                      width: 16,
                                                      height: 16,
                                                      child:
                                                          CircularProgressIndicator(
                                                        strokeWidth: 2,
                                                      ),
                                                    )
                                                  : const Text('Reject'),
                                            ),
                                          ),
                                          const SizedBox(width: 8),
                                          Expanded(
                                            child: FilledButton(
                                              onPressed: isBusy
                                                  ? null
                                                  : () => acceptInvite(invite),
                                              child: isBusy && isAccepting
                                                  ? const SizedBox(
                                                      width: 16,
                                                      height: 16,
                                                      child:
                                                          CircularProgressIndicator(
                                                        strokeWidth: 2,
                                                      ),
                                                    )
                                                  : const Text('Accept'),
                                            ),
                                          ),
                                        ],
                                      ),
                                    ],
                                  ),
                                );
                              },
                            ),
                          );
                        },
                      ),
                    ],
                  ),
                ),
              ),
            );
          },
        ),
      ),
    );
  }

  Future<void> _showSaveDestinationModal(Recipe recipe) async {
    var saveToFavorites = false;
    var saveToTry = false;
    var saveToHousehold = false;

    final shouldSave = await showModalBottomSheet<bool>(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setModalState) => SafeArea(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 10, 16, 16),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Save Recipe',
                  style: Theme.of(context).textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.w700,
                      ),
                ),
                const SizedBox(height: 8),
                SwitchListTile.adaptive(
                  contentPadding: EdgeInsets.zero,
                  secondary: const Icon(Icons.favorite_border_rounded),
                  title: const Text('My Favorites'),
                  value: saveToFavorites,
                  onChanged: (value) {
                    setModalState(() => saveToFavorites = value);
                  },
                ),
                SwitchListTile.adaptive(
                  contentPadding: EdgeInsets.zero,
                  secondary: const Icon(Icons.bookmark_border_rounded),
                  title: const Text('To Try'),
                  value: saveToTry,
                  onChanged: (value) {
                    setModalState(() => saveToTry = value);
                  },
                ),
                SwitchListTile.adaptive(
                  contentPadding: EdgeInsets.zero,
                  secondary: const Icon(Icons.home_outlined),
                  title: const Text('Household'),
                  value: saveToHousehold,
                  onChanged: (value) {
                    setModalState(() => saveToHousehold = value);
                  },
                ),
                const SizedBox(height: 8),
                SizedBox(
                  width: double.infinity,
                  child: FilledButton(
                    onPressed: () => Navigator.pop(context, true),
                    child: const Text('Save'),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
    if (shouldSave != true) return;
    await _saveRecipeToDestinations(
      recipe,
      saveToFavorites: saveToFavorites,
      saveToTry: saveToTry,
      saveToHousehold: saveToHousehold,
    );
  }

  Future<void> _saveRecipeToDestinations(
    Recipe recipe, {
    required bool saveToFavorites,
    required bool saveToTry,
    required bool saveToHousehold,
  }) async {
    final messenger = ScaffoldMessenger.of(context);
    final user = ref.read(currentUserProvider);
    if (user == null) {
      messenger.showSnackBar(
        const SnackBar(content: Text('Sign in required.')),
      );
      return;
    }
    if (!saveToFavorites && !saveToTry && !saveToHousehold) {
      messenger.showSnackBar(
        const SnackBar(content: Text('Select at least one place to save.')),
      );
      return;
    }

    try {
      final discoverRepository = ref.read(discoverRepositoryProvider);
      final personalId = await discoverRepository.saveDiscoverRecipeForUserAndReturnId(
        userId: user.id,
        recipe: recipe,
        favorite: saveToFavorites,
        toTry: saveToTry,
      );
      if (saveToHousehold) {
        await ref.read(recipesRepositoryProvider).copyPersonalRecipeToHousehold(
              userId: user.id,
              recipeId: personalId,
            );
      }

      ref.invalidate(recipesProvider);
      messenger.showSnackBar(const SnackBar(content: Text('Saved.')));
    } catch (error) {
      messenger.showSnackBar(
        SnackBar(content: Text('Could not save recipe: $error')),
      );
    }
  }

  // ignore: unused_element
  Future<void> _showFilterSheet() async {
    final initialCuisines = ref.read(discoverSelectedCuisineIdsProvider);
    final initialDietary = ref.read(discoverSelectedDietaryTagsProvider);
    final initialPrep = ref.read(discoverPrepTimeBucketProvider);
    final initialRating = ref.read(discoverRatingBucketProvider);
    final initialMeals = ref.read(discoverSelectedMealTypesProvider);

    final draftCuisines = {...initialCuisines};
    final draftDietary = {...initialDietary};
    var draftPrep = initialPrep;
    var draftRating = initialRating;
    final draftMeals = {...initialMeals};

    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      builder: (context) {
        return StatefulBuilder(
          builder: (context, setModalState) {
            Widget sectionTitle(String label) => Padding(
                  padding: const EdgeInsets.only(top: 12, bottom: 8),
                  child: Text(
                    label,
                    style: Theme.of(context).textTheme.titleSmall?.copyWith(
                          fontWeight: FontWeight.w700,
                        ),
                  ),
                );

            return SafeArea(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
                child: SingleChildScrollView(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Text(
                            'Filter & Sort',
                            style: Theme.of(context)
                                .textTheme
                                .titleLarge
                                ?.copyWith(
                                  fontWeight: FontWeight.w700,
                                ),
                          ),
                          const Spacer(),
                          TextButton(
                            onPressed: () {
                              setModalState(() {
                                draftCuisines.clear();
                                draftDietary.clear();
                                draftPrep = DiscoverPrepTimeBucket.any;
                                draftRating = DiscoverRatingBucket.any;
                                draftMeals.clear();
                              });
                            },
                            child: const Text('Clear all'),
                          ),
                        ],
                      ),
                      sectionTitle('Dietary Preferences'),
                      Wrap(
                        spacing: 8,
                        runSpacing: 8,
                        children: ['vegetarian', 'gluten-free', 'vegan', 'keto']
                            .map(
                              (tag) => FilterChip(
                                label: Text(_titleCase(tag)),
                                selected: draftDietary.contains(tag),
                                onSelected: (selected) {
                                  setModalState(() {
                                    if (selected) {
                                      draftDietary.add(tag);
                                    } else {
                                      draftDietary.remove(tag);
                                    }
                                  });
                                },
                              ),
                            )
                            .toList(),
                      ),
                      sectionTitle('Meal Type'),
                      Wrap(
                        spacing: 8,
                        runSpacing: 8,
                        children: DiscoverMealType.values
                            .map(
                              (meal) => FilterChip(
                                label: Text(meal.label),
                                selected: draftMeals.contains(meal),
                                onSelected: (selected) {
                                  setModalState(() {
                                    if (selected) {
                                      draftMeals.add(meal);
                                    } else {
                                      draftMeals.remove(meal);
                                    }
                                  });
                                },
                              ),
                            )
                            .toList(),
                      ),
                      sectionTitle('Prep Time'),
                      Wrap(
                        spacing: 8,
                        runSpacing: 8,
                        children: DiscoverPrepTimeBucket.values
                            .map(
                              (bucket) => ChoiceChip(
                                label: Text(bucket.label),
                                selected: draftPrep == bucket,
                                onSelected: (_) =>
                                    setModalState(() => draftPrep = bucket),
                              ),
                            )
                            .toList(),
                      ),
                      sectionTitle('User Rating'),
                      Wrap(
                        spacing: 8,
                        runSpacing: 8,
                        children: DiscoverRatingBucket.values
                            .map(
                              (bucket) => ChoiceChip(
                                label: Text(bucket.label),
                                selected: draftRating == bucket,
                                onSelected: (_) =>
                                    setModalState(() => draftRating = bucket),
                              ),
                            )
                            .toList(),
                      ),
                      const SizedBox(height: 18),
                      Row(
                        children: [
                          Expanded(
                            child: FilledButton(
                              onPressed: () {
                                ref
                                    .read(discoverSelectedCuisineIdsProvider
                                        .notifier)
                                    .state = draftCuisines;
                                ref
                                    .read(discoverSelectedDietaryTagsProvider
                                        .notifier)
                                    .state = draftDietary;
                                ref
                                    .read(
                                        discoverPrepTimeBucketProvider.notifier)
                                    .state = draftPrep;
                                ref
                                    .read(discoverRatingBucketProvider.notifier)
                                    .state = draftRating;
                                ref
                                    .read(discoverSelectedMealTypesProvider
                                        .notifier)
                                    .state = draftMeals;
                                Navigator.pop(context);
                              },
                              child: const Text('Apply Filters'),
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ),
            );
          },
        );
      },
    );
  }
}

class _DiscoverCuisineRecipesPage extends ConsumerWidget {
  const _DiscoverCuisineRecipesPage({
    required this.cuisineId,
    required this.title,
    required this.onOpenRecipe,
    required this.onSaveRecipe,
    required this.onShowNotifications,
  });

  final String cuisineId;
  final String title;
  final Future<void> Function(Recipe recipe) onOpenRecipe;
  final Future<void> Function(Recipe recipe) onSaveRecipe;
  final Future<void> Function() onShowNotifications;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final recipesAsync = ref.watch(discoverAllPublicRecipesProvider);
    return Scaffold(
      body: DecoratedBox(
        decoration: const BoxDecoration(
          color: AppBrand.paleMint,
        ),
        child: SafeArea(
          child: Column(
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(12, 8, 12, 8),
                child: Row(
                  children: [
                    IconButton(
                      onPressed: () => Navigator.of(context).pop(),
                      icon: const Icon(Icons.arrow_back_ios_new_rounded),
                    ),
                    Expanded(
                      child: Text(
                        title,
                        textAlign: TextAlign.center,
                        style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                              fontWeight: FontWeight.w700,
                            ),
                      ),
                    ),
                    InkWell(
                      onTap: () => context.push('/profile'),
                      borderRadius: BorderRadius.circular(18),
                      child: const CircleAvatar(
                        radius: 15,
                        backgroundColor: AppBrand.mutedAqua,
                        child: Icon(Icons.person_rounded,
                            color: AppBrand.deepTeal, size: 16),
                      ),
                    ),
                    const SizedBox(width: 8),
                    InkWell(
                      onTap: onShowNotifications,
                      borderRadius: BorderRadius.circular(16),
                      child: Container(
                        width: 32,
                        height: 32,
                        decoration: const BoxDecoration(
                          color: AppBrand.mutedAqua,
                          shape: BoxShape.circle,
                        ),
                        child: const Icon(Icons.notifications_none_rounded,
                            color: AppBrand.deepTeal, size: 18),
                      ),
                    ),
                  ],
                ),
              ),
              Expanded(
                child: Container(
                  width: double.infinity,
                  padding: const EdgeInsets.fromLTRB(12, 12, 12, 0),
                  decoration: const BoxDecoration(
                    color: AppBrand.offWhite,
                    borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
                  ),
                  child: recipesAsync.when(
                    data: (recipes) {
                      final savedRecipes =
                          ref.watch(recipesProvider).valueOrNull ??
                              const <Recipe>[];
                      final selectedMealTypes =
                          ref.watch(discoverSelectedMealTypesProvider);
                      final selectedRecipeMealTypes = selectedMealTypes
                          .map((meal) => meal.recipeMealType)
                          .toSet();
                      final filtered = recipes
                          .where((recipe) => _matchesCuisine(recipe, cuisineId))
                          .where(
                            (recipe) => selectedRecipeMealTypes.isEmpty ||
                                selectedRecipeMealTypes.contains(recipe.mealType),
                          )
                          .toList();
                      if (filtered.isEmpty) {
                        return const Center(
                          child: Text('No recipes found yet.'),
                        );
                      }
                      return GridView.builder(
                        padding: const EdgeInsets.only(bottom: 24),
                        itemCount: filtered.length,
                        gridDelegate:
                            const SliverGridDelegateWithFixedCrossAxisCount(
                          crossAxisCount: 2,
                          mainAxisSpacing: 12,
                          crossAxisSpacing: 12,
                          childAspectRatio: 0.84,
                        ),
                        itemBuilder: (context, index) {
                          final recipe = filtered[index];
                          final isSaved = _isRecipeSaved(recipe, savedRecipes);
                          final imageUrl = recipe.imageUrl?.isNotEmpty == true
                              ? _normalizeImageUrl(recipe.imageUrl!) ??
                                  recipe.imageUrl!
                              : 'https://images.unsplash.com/photo-1516100882582-96c3a05fe590?auto=format&fit=crop&w=1200&q=80';
                          return GestureDetector(
                            onTap: () => onOpenRecipe(recipe),
                            child: Container(
                              decoration: BoxDecoration(
                                borderRadius: BorderRadius.circular(12),
                                boxShadow: AppShadows.soft,
                                image: DecorationImage(
                                  image: NetworkImage(imageUrl),
                                  fit: BoxFit.cover,
                                ),
                              ),
                              child: Container(
                                decoration: BoxDecoration(
                                  borderRadius: BorderRadius.circular(12),
                                  gradient: LinearGradient(
                                    begin: Alignment.topCenter,
                                    end: Alignment.bottomCenter,
                                    colors: [
                                      Colors.black.withValues(alpha: 0.08),
                                      Colors.black.withValues(alpha: 0.65),
                                    ],
                                  ),
                                ),
                                padding: const EdgeInsets.all(8),
                                child: Column(
                                  children: [
                                    Row(
                                      children: [
                                        const Spacer(),
                                        Container(
                                          padding: const EdgeInsets.all(6),
                                          decoration: BoxDecoration(
                                            color: const Color(0xFFC8D3C2)
                                                .withValues(alpha: 0.9),
                                            borderRadius:
                                                BorderRadius.circular(10),
                                          ),
                                          child: InkWell(
                                            onTap: () => onSaveRecipe(recipe),
                                            borderRadius:
                                                BorderRadius.circular(10),
                                            child: Icon(
                                              isSaved
                                                  ? Icons.bookmark_rounded
                                                  : Icons.bookmark_border_rounded,
                                              size: 18,
                                              color: isSaved
                                                  ? const Color(0xFF2F6B46)
                                                  : const Color(0xFF2D342F),
                                            ),
                                          ),
                                        ),
                                      ],
                                    ),
                                    const Spacer(),
                                    Align(
                                      alignment: Alignment.bottomLeft,
                                      child: Text(
                                        recipe.title.toUpperCase(),
                                        maxLines: 2,
                                        overflow: TextOverflow.ellipsis,
                                        style: const TextStyle(
                                          color: Colors.white,
                                          fontWeight: FontWeight.w800,
                                          fontSize: 14,
                                          height: 1.05,
                                        ),
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ),
                          );
                        },
                      );
                    },
                    loading: () => const Center(child: CircularProgressIndicator()),
                    error: (_, __) => const Center(
                      child: Text('Could not load recipes right now.'),
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

bool _matchesCuisine(Recipe recipe, String cuisineId) {
  final haystack = '${recipe.title} ${recipe.cuisineTags.join(' ')}'.toLowerCase();
  switch (cuisineId) {
    case 'pasta':
      return _hasAny(haystack, const <String>['pasta', 'spaghetti', 'italian']);
    case 'mexican-fiesta':
      return _hasAny(haystack, const <String>['mexican', 'taco', 'fajita', 'burrito']);
    case 'asian':
      return _hasAny(haystack, const <String>['asian', 'ramen', 'stir-fry', 'noodle']);
    case 'plant-based-power':
      return _hasAny(haystack, const <String>['plant', 'vegetarian', 'veggie']);
    case 'whole30':
      return _hasAny(
        haystack,
        const <String>['whole30', 'whole 30', 'paleo', 'grain-free', 'dairy-free'],
      );
    case 'high-protein':
      return _hasAny(haystack, const <String>['high-protein', 'high protein', 'protein']);
    case 'healthy':
      return _hasAny(haystack, const <String>['healthy', 'wellness', 'clean', 'nourishing']);
    case 'pancakes':
      return _hasAny(haystack, const <String>['pancake', 'waffle', 'crepe', 'hotcake']);
    case 'breakfast-casserole':
      return _hasAny(
        haystack,
        const <String>[
          'breakfast casserole',
          'breakfast',
          'egg bake',
          'scrambled',
          'scramble',
          'strata',
          'frittata',
          'hash',
          'potato',
        ],
      );
    case 'bento-box-lunch':
      return _hasAny(
        haystack,
        const <String>['bento', 'lunch box', 'box lunch', 'meal prep lunch'],
      );
    case 'healthy-lunch':
      return _hasAny(
        haystack,
        const <String>[
          'healthy lunch',
          'lunch ideas',
          'meal prep lunch',
          'light lunch',
          'nourishing',
        ],
      );
    case 'salads':
      return _hasAny(
        haystack,
        const <String>['salad', 'vinaigrette', 'greens', 'caesar'],
      );
    case 'sandwiches-wraps':
      return _hasAny(
        haystack,
        const <String>['sandwich', 'wrap', 'panini', 'melt', 'hoagie', 'sub'],
      );
    case 'vegetarian':
      return _hasAny(
        haystack,
        const <String>['vegetarian', 'veggie', 'plant-based', 'meatless'],
      );
    case 'comfort-classics':
      return _hasAny(haystack, const <String>['comfort', 'classic', 'baked', 'creamy']);
    case 'vegan-delights':
      return _hasAny(haystack, const <String>['vegan']);
    case 'mediterranean-flavors':
      return _hasAny(haystack, const <String>['mediterranean', 'greek', 'orzo']);
    case 'snack-dips-spreads':
      return _hasAny(
        haystack,
        const <String>[
          'dip',
          'hummus',
          'guacamole',
          'salsa',
          'tapenade',
          'tzatziki',
          'muhammara',
          'whipped feta',
        ],
      );
    case 'snack-finger-foods':
      return _hasAny(
        haystack,
        const <String>[
          'finger food',
          'bites',
          'skewer',
          'roll',
          'taquito',
          'dumpling',
          'poppers',
          'deviled eggs',
        ],
      );
    case 'snack-boards-platters':
      return _hasAny(
        haystack,
        const <String>[
          'board',
          'platter',
          'charcuterie',
          'cheese board',
          'crudite',
          'mezze',
          'nachos',
        ],
      );
    case 'snack-cheesy-bakes':
      return _hasAny(
        haystack,
        const <String>[
          'baked brie',
          'cheese log',
          'potato skins',
          'spinach artichoke',
          'cheese',
        ],
      );
    case 'snack-wings-meaty-bites':
      return _hasAny(
        haystack,
        const <String>[
          'wings',
          'meatballs',
          'sausage rolls',
          'buffalo',
          'chicken',
          'bacon',
        ],
      );
    case 'snack-seafood-appetizers':
      return _hasAny(
        haystack,
        const <String>['shrimp', 'prawns', 'smoked salmon', 'ceviche', 'fish'],
      );
    case 'snack-crispy-snacks':
      return _hasAny(
        haystack,
        const <String>[
          'fries',
          'onion rings',
          'fried pickles',
          'zucchini fries',
          'chips',
          'popcorn',
        ],
      );
    case 'snack-healthy-veggie-snacks':
      return _hasAny(
        haystack,
        const <String>[
          'cauliflower',
          'mushrooms',
          'vegetarian',
          'vegan',
          'veggie',
          'nuts',
          'seeds',
        ],
      );
    case 'dessert-chocolate':
      return _hasAny(
        haystack,
        const <String>['chocolate', 'brownie', 'mousse', 'cacao', 'fudge'],
      );
    case 'dessert-cookies-bars':
      return _hasAny(
        haystack,
        const <String>[
          'cookie',
          'bars',
          'shortbread',
          'snickerdoodle',
          'thumbprint',
        ],
      );
    case 'dessert-cakes-cupcakes':
      return _hasAny(
        haystack,
        const <String>['cake', 'cupcake', 'layer cake', 'pound cake'],
      );
    case 'dessert-muffins-breads':
      return _hasAny(
        haystack,
        const <String>['muffin', 'banana bread', 'zucchini bread', 'quick bread'],
      );
    case 'dessert-pies-cobblers-crisps':
      return _hasAny(
        haystack,
        const <String>['pie', 'cobbler', 'crisp', 'crumble', 'tart'],
      );
    case 'dessert-fruit':
      return _hasAny(
        haystack,
        const <String>['fruit', 'berries', 'strawberry', 'peach', 'apple', 'cherry'],
      );
    case 'dessert-no-bake':
      return _hasAny(
        haystack,
        const <String>['no-bake', 'energy balls', 'protein balls', 'truffles'],
      );
    case 'dessert-frozen-creamy':
      return _hasAny(
        haystack,
        const <String>['ice cream', 'pudding', 'panna cotta', 'affogato', 'custard'],
      );
    case 'dinner-chicken':
      return _hasAny(haystack, const <String>['chicken', 'poultry']);
    case 'dinner-beef':
      return _hasAny(haystack, const <String>['beef', 'steak', 'brisket']);
    case 'dinner-pasta':
      return _hasAny(
        haystack,
        const <String>['pasta', 'spaghetti', 'italian', 'penne', 'linguine'],
      );
    case 'dinner-pork':
      return _hasAny(haystack, const <String>['pork', 'bacon', 'ham', 'sausage']);
    case 'dinner-vegetarian':
      return _hasAny(
        haystack,
        const <String>['vegetarian', 'plant-based', 'veggie', 'plant', 'tofu'],
      );
    case 'dinner-seafood':
      return _hasAny(
        haystack,
        const <String>['seafood', 'salmon', 'shrimp', 'fish', 'scallop', 'cod'],
      );
    case 'dinner-one-pan':
      return _hasAny(
        haystack,
        const <String>[
          'one-pan',
          'one pan',
          'sheet pan',
          'sheet-pan',
          'skillet',
        ],
      );
    case 'dinner-southern':
      return _hasAny(
        haystack,
        const <String>[
          'southern',
          'comfort',
          'grits',
          'biscuit',
          'cajun',
          'fried',
        ],
      );
    case 'dinner-crockpot':
      return _hasAny(
        haystack,
        const <String>['crockpot', 'slow cooker', 'slow-cooker'],
      );
    case 'dinner-instant-pot':
      return _hasAny(
        haystack,
        const <String>['instant pot', 'instant-pot', 'pressure cooker'],
      );
    case 'dinner-grill':
      return _hasAny(haystack, const <String>['grill', 'grilled', 'bbq', 'skewer']);
    case 'dinner-soup':
      return _hasAny(
        haystack,
        const <String>['soup', 'stew', 'chowder', 'bisque', 'broth', 'chili'],
      );
    default:
      return false;
  }
}

bool _hasAny(String haystack, List<String> needles) {
  for (final keyword in needles) {
    if (haystack.contains(keyword)) return true;
  }
  return false;
}

bool _isRecipeSaved(Recipe discoverRecipe, List<Recipe> savedRecipes) {
  final discoverSourceUrl = (discoverRecipe.sourceUrl ?? '').trim();
  final discoverApiId = (discoverRecipe.apiId ?? '').trim();
  final discoverTitle = discoverRecipe.title.trim().toLowerCase();
  final discoverMealType = discoverRecipe.mealType.name;

  for (final saved in savedRecipes) {
    final savedSourceUrl = (saved.sourceUrl ?? '').trim();
    final savedApiId = (saved.apiId ?? '').trim();
    if (discoverSourceUrl.isNotEmpty && discoverSourceUrl == savedSourceUrl) {
      return true;
    }
    if (discoverApiId.isNotEmpty && discoverApiId == savedApiId) {
      return true;
    }
    if (saved.title.trim().toLowerCase() == discoverTitle &&
        saved.mealType.name == discoverMealType) {
      return true;
    }
  }
  return false;
}

class _DiscoverRecipeDetailPage extends ConsumerStatefulWidget {
  const _DiscoverRecipeDetailPage({required this.recipe});

  final Recipe recipe;

  @override
  ConsumerState<_DiscoverRecipeDetailPage> createState() =>
      _DiscoverRecipeDetailPageState();
}

class _DiscoverRecipeDetailPageState
    extends ConsumerState<_DiscoverRecipeDetailPage> {
  _DiscoverDetailSection _selectedSection = _DiscoverDetailSection.ingredients;
  late bool _isFavorite = widget.recipe.isFavorite;
  late bool _isToTry = widget.recipe.isToTry;

  @override
  Widget build(BuildContext context) {
    final recipe = widget.recipe;
    return Scaffold(
      body: CustomScrollView(
        slivers: [
          const SliverAppBar(
            pinned: true,
            centerTitle: true,
            title: Text('Discover'),
            actions: [
              CircleAvatar(
                radius: 12,
                backgroundColor: AppBrand.mutedAqua,
                child: Icon(Icons.person_rounded,
                    size: 14, color: AppBrand.deepTeal),
              ),
              SizedBox(width: 8),
              Icon(
                Icons.notifications_none_rounded,
                size: 18,
                color: AppBrand.deepTeal,
              ),
              SizedBox(width: 8),
            ],
          ),
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(12, 12, 12, 120),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      ClipRRect(
                        borderRadius: BorderRadius.circular(12),
                        child: Container(
                          width: 124,
                          height: 124,
                          color: const Color(0xFFE8E1D4),
                          child: FoodMedia(
                            imageUrl: recipe.imageUrl,
                            fit: BoxFit.cover,
                          ),
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          children: [
                            _summaryStatTile(
                              context,
                              icon: Icons.timer_outlined,
                              label: 'Cook Time',
                              value: _totalTimeLabel(recipe),
                            ),
                            const SizedBox(height: 8),
                            _summaryStatTile(
                              context,
                              icon: Icons.people_outline_rounded,
                              label: 'Servings',
                              value: '${recipe.servings}',
                            ),
                            const SizedBox(height: 8),
                            _summaryStatTile(
                              context,
                              icon: Icons.local_fire_department_outlined,
                              label: 'Calories',
                              value: recipe.nutrition.calories > 0
                                  ? '${recipe.nutrition.calories}'
                                  : 'N/A',
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  Text(
                    recipe.title,
                    style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                          fontWeight: FontWeight.w800,
                          height: 1.15,
                        ),
                  ),
                  const SizedBox(height: 12),
                  _buildDetailSectionChips(),
                  const SizedBox(height: 12),
                  _buildDetailSectionContent(context, recipe),
                ],
              ),
            ),
          ),
        ],
      ),
      bottomNavigationBar: SafeArea(
        minimum: const EdgeInsets.fromLTRB(12, 8, 12, 10),
        child: Row(
          children: [
            Expanded(
              child: FilledButton.icon(
                onPressed: () => _setRecipeFlag(favorite: !_isFavorite),
                icon: Icon(
                  _isFavorite
                      ? Icons.favorite_rounded
                      : Icons.favorite_border_rounded,
                ),
                label: Text(_isFavorite ? 'Favorited' : 'Favorite'),
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: FilledButton.tonalIcon(
                onPressed: () => _setRecipeFlag(toTry: !_isToTry),
                icon: const Icon(Icons.bookmark_add_outlined),
                label: Text(_isToTry ? 'In To Try' : 'To Try'),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _summaryStatTile(
    BuildContext context, {
    required IconData icon,
    required String label,
    required String value,
  }) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
      decoration: BoxDecoration(
        color: const Color(0xFFF1EEE6),
        borderRadius: BorderRadius.circular(10),
      ),
      child: Row(
        children: [
          Icon(icon, size: 16, color: const Color(0xFF4F5D52)),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              label,
              style: Theme.of(context).textTheme.labelMedium?.copyWith(
                    color: const Color(0xFF5B645D),
                    fontWeight: FontWeight.w600,
                  ),
            ),
          ),
          Text(
            value,
            style: Theme.of(context).textTheme.labelLarge?.copyWith(
                  fontWeight: FontWeight.w700,
                ),
          ),
        ],
      ),
    );
  }

  Widget _buildDetailSectionChips() {
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: Row(
        children: _DiscoverDetailSection.values
            .map(
              (section) => Padding(
                padding: const EdgeInsets.only(right: 8),
                child: ChoiceChip(
                  label: Text(section.label),
                  selected: _selectedSection == section,
                  onSelected: (_) => setState(() => _selectedSection = section),
                ),
              ),
            )
            .toList(),
      ),
    );
  }

  Widget _buildDetailSectionContent(BuildContext context, Recipe recipe) {
    switch (_selectedSection) {
      case _DiscoverDetailSection.ingredients:
        return SectionCard(
          title: 'Ingredients',
          titleTrailing: const MeasurementSystemToggle(),
          child: _buildIngredientsTable(context, ref, recipe),
        );
      case _DiscoverDetailSection.directions:
        return SectionCard(
          title: 'Directions',
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: recipe.instructions.isEmpty
                ? const [Text('No instructions available yet.')]
                : recipe.instructions
                    .map(
                      (step) => Padding(
                        padding: const EdgeInsets.only(bottom: 6),
                        child: Text(_decodeHtmlEntities(step)),
                      ),
                    )
                    .toList(),
          ),
        );
      case _DiscoverDetailSection.nutritionalInfo:
        return SectionCard(
          title: 'Nutritional Info',
          child: _nutritionGrid(context, recipe),
        );
    }
  }

  Widget _nutritionGrid(BuildContext context, Recipe recipe) {
    final nutrition = recipe.nutrition;
    final hasNutrition = nutrition.calories > 0 ||
        nutrition.protein > 0 ||
        nutrition.fat > 0 ||
        nutrition.carbs > 0;
    if (!hasNutrition) {
      return const Text('Data loading soon');
    }

    Widget tile({
      required IconData icon,
      required String label,
      required String value,
    }) {
      return Container(
        padding: const EdgeInsets.all(10),
        decoration: BoxDecoration(
          color: Theme.of(context).colorScheme.surfaceContainerHighest,
          borderRadius: BorderRadius.circular(12),
        ),
        child: Row(
          children: [
            Icon(icon, size: 18),
            const SizedBox(width: 8),
            Expanded(child: Text(label)),
            Text(value, style: const TextStyle(fontWeight: FontWeight.w700)),
          ],
        ),
      );
    }

    return Column(
      children: [
        tile(
          icon: Icons.local_fire_department_rounded,
          label: 'Calories',
          value: '${nutrition.calories}',
        ),
        const SizedBox(height: 8),
        tile(
          icon: Icons.fitness_center_rounded,
          label: 'Protein',
          value: '${nutrition.protein.toStringAsFixed(1)}g',
        ),
        const SizedBox(height: 8),
        tile(
          icon: Icons.opacity_rounded,
          label: 'Fat',
          value: '${nutrition.fat.toStringAsFixed(1)}g',
        ),
        const SizedBox(height: 8),
        tile(
          icon: Icons.grain_rounded,
          label: 'Carbs',
          value: '${nutrition.carbs.toStringAsFixed(1)}g',
        ),
      ],
    );
  }

  Widget _buildIngredientsTable(
    BuildContext context,
    WidgetRef ref,
    Recipe recipe,
  ) {
    if (recipe.ingredients.isEmpty) {
      return const Text('No ingredients available yet.');
    }

    final measurementSystem = ref.watch(measurementSystemProvider);
    final scheme = Theme.of(context).colorScheme;
    final amountHeader =
        MediaQuery.sizeOf(context).width < 380 ? 'Amt.' : 'Amount';

    TableRow headerRow() {
      return TableRow(
        decoration: BoxDecoration(
          color: scheme.primaryContainer.withValues(alpha: 0.55),
        ),
        children: [
          const _IngredientTableCell(
            text: 'Ingredient',
            isHeader: true,
            noWrap: true,
          ),
          _IngredientTableCell(
            text: amountHeader,
            isHeader: true,
            noWrap: true,
          ),
          const _IngredientTableCell(
            text: 'Unit',
            isHeader: true,
            noWrap: true,
          ),
        ],
      );
    }

    final ingredientRows = recipe.ingredients.asMap().entries.map((entry) {
      final index = entry.key;
      final ingredient = entry.value;
      final cols = ingredientDisplayColumns(ingredient, measurementSystem);
      final amount = cols.amount;
      final evenRow = index.isEven;
      final unit = cols.unit;
      return TableRow(
        decoration: BoxDecoration(
          color: evenRow
              ? scheme.surfaceContainerHighest.withValues(alpha: 0.45)
              : scheme.surface,
        ),
        children: [
          _IngredientTableCell(text: ingredient.name),
          _IngredientTableCell(text: amount, noWrap: true),
          _IngredientTableCell(
            text: unit.isEmpty ? '-' : unit,
            noWrap: true,
          ),
        ],
      );
    }).toList();

    return ClipRRect(
      borderRadius: BorderRadius.circular(12),
      child: Table(
        border: TableBorder(
          horizontalInside: BorderSide(color: scheme.outlineVariant),
          verticalInside: BorderSide(color: scheme.outlineVariant),
          top: BorderSide(color: scheme.outlineVariant),
          bottom: BorderSide(color: scheme.outlineVariant),
          left: BorderSide(color: scheme.outlineVariant),
          right: BorderSide(color: scheme.outlineVariant),
        ),
        columnWidths: const <int, TableColumnWidth>{
          0: FlexColumnWidth(2.1),
          1: FlexColumnWidth(1.35),
          2: FlexColumnWidth(1.0),
        },
        defaultVerticalAlignment: TableCellVerticalAlignment.top,
        children: [
          headerRow(),
          ...ingredientRows,
        ],
      ),
    );
  }

  Future<void> _setRecipeFlag({bool? favorite, bool? toTry}) async {
    final messenger = ScaffoldMessenger.of(context);
    try {
      final user = ref.read(currentUserProvider);
      if (user == null) {
        messenger.showSnackBar(
          const SnackBar(content: Text('Sign in required.')),
        );
        return;
      }
      final repository = ref.read(discoverRepositoryProvider);
      await repository.saveDiscoverRecipeForUser(
        userId: user.id,
        recipe: widget.recipe,
        favorite: favorite,
        toTry: toTry,
      );
      if (favorite != null) setState(() => _isFavorite = favorite);
      if (toTry != null) setState(() => _isToTry = toTry);
      ref.invalidate(discoverPublicRecipesProvider);
      ref.invalidate(recipesProvider);
      messenger.showSnackBar(const SnackBar(content: Text('Saved.')));
    } catch (error) {
      messenger.showSnackBar(
        SnackBar(content: Text('Could not update recipe: $error')),
      );
    }
  }

  String _totalTimeLabel(Recipe recipe) {
    final minutes = (recipe.prepTime ?? 0) + (recipe.cookTime ?? 0);
    return minutes > 0 ? '$minutes min' : 'Quick';
  }
}

enum _DiscoverDetailSection {
  ingredients('Ingredients'),
  directions('Directions'),
  nutritionalInfo('Nutritional Info');

  const _DiscoverDetailSection(this.label);
  final String label;
}

class _IngredientTableCell extends StatelessWidget {
  const _IngredientTableCell({
    required this.text,
    this.isHeader = false,
    this.noWrap = false,
  });

  final String text;
  final bool isHeader;
  final bool noWrap;

  @override
  Widget build(BuildContext context) {
    final style = isHeader
        ? Theme.of(context).textTheme.labelLarge?.copyWith(
              fontWeight: FontWeight.w700,
            )
        : Theme.of(context).textTheme.bodyMedium;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 10),
      child: Text(
        text,
        style: style,
        softWrap: !noWrap,
        overflow: noWrap ? TextOverflow.fade : TextOverflow.visible,
        maxLines: noWrap ? 1 : null,
      ),
    );
  }
}

String _titleCase(String input) {
  if (input.isEmpty) return input;
  return input
      .split('-')
      .where((part) => part.isNotEmpty)
      .map((part) => '${part[0].toUpperCase()}${part.substring(1)}')
      .join(' ');
}

String _fallbackFoodImage(int index) {
  const images = <String>[
    'https://images.unsplash.com/photo-1546069901-ba9599a7e63c?w=900&q=80',
    'https://images.unsplash.com/photo-1512621776951-a57141f2eefd?w=900&q=80',
    'https://images.unsplash.com/photo-1512058564366-18510be2db19?w=900&q=80',
    'https://images.unsplash.com/photo-1504674900247-0877df9cc836?w=900&q=80',
    'https://images.unsplash.com/photo-1473093295043-cdd812d0e601?w=900&q=80',
    'https://images.unsplash.com/photo-1482049016688-2d3e1b311543?w=900&q=80',
  ];
  return images[index % images.length];
}

String? _normalizeImageUrl(String? rawUrl) {
  if (rawUrl == null) return null;
  final trimmed = rawUrl.trim();
  if (trimmed.isEmpty) return null;
  final uri = Uri.tryParse(trimmed);
  if (uri == null) return trimmed;
  if (uri.scheme.toLowerCase() == 'http') {
    return uri.replace(scheme: 'https').toString();
  }
  return trimmed;
}

String _decodeHtmlEntities(String input) {
  return input
      .replaceAll('&#215;', '×')
      .replaceAll('&times;', '×')
      .replaceAll('&#8217;', "'")
      .replaceAll('&#8216;', "'")
      .replaceAll('&#8220;', '"')
      .replaceAll('&#8221;', '"')
      .replaceAll('&#8211;', '-')
      .replaceAll('&#8212;', '-')
      .replaceAll('&amp;', '&')
      .replaceAll('&quot;', '"')
      .replaceAll('&#39;', "'")
      .replaceAll('&apos;', "'")
      .replaceAll('&lt;', '<')
      .replaceAll('&gt;', '>');
}


String _cuisineGraphicForLabel(String label) {
  final key = label.toLowerCase();
  const curatedByLabel = <String, String>{
    // Appetizers & Snacks
    'dips & spreads':
        'https://cdn.jsdelivr.net/gh/twitter/twemoji@14.0.2/assets/72x72/1f95f.png',
    'finger foods':
        'https://cdn.jsdelivr.net/gh/twitter/twemoji@14.0.2/assets/72x72/1f96f.png',
    'boards & platters':
        'https://cdn.jsdelivr.net/gh/twitter/twemoji@14.0.2/assets/72x72/1f9c0.png',
    'cheesy bakes':
        'https://cdn.jsdelivr.net/gh/twitter/twemoji@14.0.2/assets/72x72/1f9c8.png',
    'wings & meaty bites':
        'https://cdn.jsdelivr.net/gh/twitter/twemoji@14.0.2/assets/72x72/1f357.png',
    'seafood appetizers':
        'https://cdn.jsdelivr.net/gh/twitter/twemoji@14.0.2/assets/72x72/1f990.png',
    'crispy snacks':
        'https://cdn.jsdelivr.net/gh/twitter/twemoji@14.0.2/assets/72x72/1f35f.png',
    'healthy & veggie':
        'https://cdn.jsdelivr.net/gh/twitter/twemoji@14.0.2/assets/72x72/1f96c.png',

    // Dinner
    'chicken':
        'https://cdn.jsdelivr.net/gh/twitter/twemoji@14.0.2/assets/72x72/1f357.png',
    'beef':
        'https://cdn.jsdelivr.net/gh/twitter/twemoji@14.0.2/assets/72x72/1f969.png',
    'pasta':
        'https://cdn.jsdelivr.net/gh/twitter/twemoji@14.0.2/assets/72x72/1f35d.png',
    'pork':
        'https://cdn.jsdelivr.net/gh/twitter/twemoji@14.0.2/assets/72x72/1f356.png',
    'vegetarian':
        'https://cdn.jsdelivr.net/gh/twitter/twemoji@14.0.2/assets/72x72/1f331.png',
    'seafood':
        'https://cdn.jsdelivr.net/gh/twitter/twemoji@14.0.2/assets/72x72/1f41f.png',
    'one-pan & sheet pan':
        'https://cdn.jsdelivr.net/gh/twitter/twemoji@14.0.2/assets/72x72/1f373.png',
    'southern comfort':
        'https://cdn.jsdelivr.net/gh/twitter/twemoji@14.0.2/assets/72x72/1f372.png',
    'crockpot':
        'https://cdn.jsdelivr.net/gh/twitter/twemoji@14.0.2/assets/72x72/1f958.png',
    'instant pot':
        'https://cdn.jsdelivr.net/gh/twitter/twemoji@14.0.2/assets/72x72/1f35b.png',
    'grill':
        'https://cdn.jsdelivr.net/gh/twitter/twemoji@14.0.2/assets/72x72/1f525.png',
    'soups':
        'https://cdn.jsdelivr.net/gh/twitter/twemoji@14.0.2/assets/72x72/1f35c.png',

    // Desserts
    'chocolate':
        'https://cdn.jsdelivr.net/gh/twitter/twemoji@14.0.2/assets/72x72/1f36b.png',
    'cookies & bars':
        'https://cdn.jsdelivr.net/gh/twitter/twemoji@14.0.2/assets/72x72/1f36a.png',
    'cakes & cupcakes':
        'https://cdn.jsdelivr.net/gh/twitter/twemoji@14.0.2/assets/72x72/1f370.png',
    'muffins & quick breads':
        'https://cdn.jsdelivr.net/gh/twitter/twemoji@14.0.2/assets/72x72/1f9c1.png',
    'pies, cobblers & crisps':
        'https://cdn.jsdelivr.net/gh/twitter/twemoji@14.0.2/assets/72x72/1f967.png',
    'fruit desserts':
        'https://cdn.jsdelivr.net/gh/twitter/twemoji@14.0.2/assets/72x72/1f352.png',
    'no-bake':
        'https://cdn.jsdelivr.net/gh/twitter/twemoji@14.0.2/assets/72x72/1f95c.png',
    'frozen & creamy':
        'https://cdn.jsdelivr.net/gh/twitter/twemoji@14.0.2/assets/72x72/1f366.png',
  };

  final curated = curatedByLabel[key];
  if (curated != null) return curated;

  if (key.contains('mexican') || key.contains('taco')) {
    return 'https://cdn.jsdelivr.net/gh/twitter/twemoji@14.0.2/assets/72x72/1f32e.png';
  }
  if (key.contains('italian') ||
      key.contains('pasta') ||
      key.contains('spaghetti')) {
    return 'https://cdn.jsdelivr.net/gh/twitter/twemoji@14.0.2/assets/72x72/1f35d.png';
  }
  if (key.contains('asian') || key.contains('stir') || key.contains('noodle')) {
    return 'https://cdn.jsdelivr.net/gh/twitter/twemoji@14.0.2/assets/72x72/1f35c.png';
  }
  if (key.contains('plant') ||
      key.contains('vegan') ||
      key.contains('vegetarian')) {
    return 'https://cdn.jsdelivr.net/gh/twitter/twemoji@14.0.2/assets/72x72/1f331.png';
  }
  if (key.contains('whole30') || key.contains('whole 30') || key.contains('paleo')) {
    return 'https://cdn.jsdelivr.net/gh/twitter/twemoji@14.0.2/assets/72x72/1f95d.png';
  }
  if (key.contains('high-protein') || key.contains('protein')) {
    return 'https://cdn.jsdelivr.net/gh/twitter/twemoji@14.0.2/assets/72x72/1f4aa.png';
  }
  if (key.contains('healthy') || key.contains('wellness')) {
    return 'https://cdn.jsdelivr.net/gh/twitter/twemoji@14.0.2/assets/72x72/1f957.png';
  }
  if (key.contains('pancake')) {
    return 'https://cdn.jsdelivr.net/gh/twitter/twemoji@14.0.2/assets/72x72/1f95e.png';
  }
  if (key.contains('bento')) {
    return 'https://cdn.jsdelivr.net/gh/twitter/twemoji@14.0.2/assets/72x72/1f371.png';
  }
  if (key.contains('healthy lunch')) {
    return 'https://cdn.jsdelivr.net/gh/twitter/twemoji@14.0.2/assets/72x72/1f957.png';
  }
  if (key.contains('salad')) {
    return 'https://cdn.jsdelivr.net/gh/twitter/twemoji@14.0.2/assets/72x72/1f96c.png';
  }
  if (key.contains('sandwich') || key.contains('wrap')) {
    return 'https://cdn.jsdelivr.net/gh/twitter/twemoji@14.0.2/assets/72x72/1f96a.png';
  }
  if (key.contains('vegetarian')) {
    return 'https://cdn.jsdelivr.net/gh/twitter/twemoji@14.0.2/assets/72x72/1f33f.png';
  }
  if (key.contains('casserole') ||
      key.contains('strata') ||
      key.contains('egg bake') ||
      key.contains('hearty breakfast')) {
    return 'https://cdn.jsdelivr.net/gh/twitter/twemoji@14.0.2/assets/72x72/1f373.png';
  }
  if (key.contains('comfort') || key.contains('classic')) {
    return 'https://cdn.jsdelivr.net/gh/twitter/twemoji@14.0.2/assets/72x72/1f372.png';
  }
  if (key.contains('mediterranean') || key.contains('greek')) {
    return 'https://cdn.jsdelivr.net/gh/twitter/twemoji@14.0.2/assets/72x72/1f9c6.png';
  }
  if (key.contains('american') || key.contains('burger')) {
    return 'https://cdn.jsdelivr.net/gh/twitter/twemoji@14.0.2/assets/72x72/1f354.png';
  }
  if (key.contains('japanese') || key.contains('ramen')) {
    return 'https://cdn.jsdelivr.net/gh/twitter/twemoji@14.0.2/assets/72x72/1f35c.png';
  }
  if (key.contains('breakfast') || key.contains('pancake')) {
    return 'https://cdn.jsdelivr.net/gh/twitter/twemoji@14.0.2/assets/72x72/1f95e.png';
  }
  return 'https://cdn.jsdelivr.net/gh/twitter/twemoji@14.0.2/assets/72x72/1f372.png';
}
