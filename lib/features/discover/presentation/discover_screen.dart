import 'dart:math' show Random;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:plateplan/core/measurement/ingredient_display_units.dart';
import 'package:plateplan/core/measurement/measurement_system_provider.dart';
import 'package:plateplan/core/models/app_models.dart';
import 'package:plateplan/core/models/dietary_option.dart';
import 'package:plateplan/core/theme/app_brand.dart';
import 'package:plateplan/core/theme/design_tokens.dart';
import 'package:plateplan/core/ui/measurement_system_toggle.dart';
import 'package:plateplan/core/ui/recipo_kit.dart';
import 'package:plateplan/core/ui/section_card.dart';
import 'package:plateplan/features/auth/data/auth_providers.dart';
import 'package:plateplan/features/discover/data/discover_repository.dart';
import 'package:plateplan/features/discover/domain/discover_browse_categories.dart';
import 'package:plateplan/features/grocery/data/grocery_repository.dart';
import 'package:plateplan/features/household/data/household_providers.dart';
import 'package:plateplan/features/planner/data/planner_repository.dart';
import 'package:plateplan/features/profile/data/profile_providers.dart';
import 'package:plateplan/features/recipes/data/recipes_repository.dart';
import 'package:plateplan/features/recipes/presentation/recipe_household_copy.dart';

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
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      ref.read(discoverBreakfastFeaturedShuffleSeedProvider.notifier).state =
          Random().nextInt(0x3fffffff);
      ref.read(discoverLunchFeaturedShuffleSeedProvider.notifier).state =
          Random().nextInt(0x3fffffff);
      ref.read(discoverDinnerFeaturedShuffleSeedProvider.notifier).state =
          Random().nextInt(0x3fffffff);
    });
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    ref.listen<DiscoverMealType>(discoverMealTypeProvider, (previous, next) {
      if (next == DiscoverMealType.entree && previous != DiscoverMealType.entree) {
        ref.read(discoverBreakfastFeaturedShuffleSeedProvider.notifier).state =
            Random().nextInt(0x3fffffff);
      }
      if (next == DiscoverMealType.side && previous != DiscoverMealType.side) {
        ref.read(discoverLunchFeaturedShuffleSeedProvider.notifier).state =
            Random().nextInt(0x3fffffff);
      }
      if (next == DiscoverMealType.sauce && previous != DiscoverMealType.sauce) {
        ref.read(discoverDinnerFeaturedShuffleSeedProvider.notifier).state =
            Random().nextInt(0x3fffffff);
      }
    });
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
        ? 'Breakfast Ideas'
        : isLunchOnlySelected
            ? 'Lunch Ideas'
            : isSnackOnlySelected
                ? 'Snack Ideas'
                : isDessertOnlySelected
                    ? 'Dessert Ideas'
                    : 'Dinner Ideas';
    final cuisinesAsync = ref.watch(discoverCuisineTilesProvider);
    final searchQuery = ref.watch(discoverSearchQueryProvider);
    final isSearchActive = searchQuery.trim().isNotEmpty;
    final searchResultsAsync = ref.watch(discoverPublicSearchResultsProvider);
    final activeDietary = ref.watch(discoverSelectedDietaryTagsProvider);

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
                    _buildSearchOnly(isSearchActive: isSearchActive),
                    if (activeDietary.isNotEmpty) ...[
                      const SizedBox(height: AppSpacing.xs),
                      _buildActiveDietaryFiltersRow(activeDietary),
                    ],
                    const SizedBox(height: AppSpacing.sm),
                    if (!isSearchActive) ...[
                      _buildMealTypeChips(selectedMeal),
                      const SizedBox(height: AppSpacing.md),
                    ],
                  ],
                ),
              ),
              Expanded(
                child: isSearchActive
                    ? _buildSearchResultsBody(searchResultsAsync)
                    : ListView(
                        padding: const EdgeInsets.fromLTRB(12, 0, 12, 16),
                        children: [
                          Container(
                            padding: const EdgeInsets.fromLTRB(12, 12, 12, 10),
                            decoration: const BoxDecoration(
                              color: AppBrand.offWhite,
                              borderRadius:
                                  BorderRadius.vertical(top: Radius.circular(20)),
                            ),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                _sectionTitle(context, featuredSectionTitle),
                                const SizedBox(height: AppSpacing.xs),
                                _buildQuickDinnerGrid(featuredRecipesAsync),
                                const SizedBox(height: AppSpacing.md),
                                _sectionTitle(context, 'Explore Cuisines'),
                                if (activeDietary.isNotEmpty)
                                  Padding(
                                    padding: const EdgeInsets.only(bottom: 4),
                                    child: GestureDetector(
                                      onTap: _showFilterSheet,
                                      child: Text(
                                        'Filtered for ${activeDietary.map((s) {
                                          for (final o in DietaryOption.values) {
                                            if (o.slug == s) return o.label;
                                          }
                                          return s;
                                        }).join(', ')}',
                                        style: Theme.of(context)
                                            .textTheme
                                            .bodySmall
                                            ?.copyWith(
                                              color: AppBrand.deepTeal,
                                            ),
                                      ),
                                    ),
                                  ),
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

  void _clearDiscoverSearch() {
    _searchController.clear();
    ref.read(discoverSearchQueryProvider.notifier).state = '';
  }

  Widget _buildSearchResultsBody(AsyncValue<List<Recipe>> searchAsync) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(12, 0, 12, 16),
      decoration: const BoxDecoration(
        color: AppBrand.offWhite,
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      child: searchAsync.when(
        data: (recipes) {
          if (recipes.isEmpty) {
            return const Center(
              child: Padding(
                padding: EdgeInsets.all(24),
                child: Text('No recipes found.'),
              ),
            );
          }
          final savedRecipes =
              ref.watch(recipesProvider).valueOrNull ?? const <Recipe>[];
          final userId = ref.watch(currentUserProvider)?.id;
          return GridView.builder(
            padding: const EdgeInsets.fromLTRB(0, 12, 0, 8),
            itemCount: recipes.length,
            gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
              crossAxisCount: 2,
              mainAxisSpacing: 12,
              crossAxisSpacing: 12,
              childAspectRatio: 0.84,
            ),
            itemBuilder: (context, index) {
              final recipe = recipes[index];
              final imageUrl = recipe.imageUrl?.isNotEmpty == true
                  ? _normalizeImageUrl(recipe.imageUrl!) ?? recipe.imageUrl!
                  : 'https://images.unsplash.com/photo-1516100882582-96c3a05fe590?auto=format&fit=crop&w=1200&q=80';
              return GestureDetector(
                onTap: () => _showPublicRecipeDetail(recipe),
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
                            _discoverSaveAffordance(
                              context: context,
                              recipe: recipe,
                              savedRecipes: savedRecipes,
                              userId: userId,
                              onOpenSheet: () => _showSaveDestinationModal(recipe),
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
    );
  }

  Widget _buildHeader(BuildContext context) {
    final filterCount = ref.watch(discoverActiveFilterCountProvider);
    return Row(
      children: [
        InkWell(
          onTap: _showFilterSheet,
          borderRadius: BorderRadius.circular(14),
          child: Badge(
            isLabelVisible: filterCount > 0,
            label: Text('$filterCount'),
            offset: const Offset(6, -4),
            child: const Icon(
              Icons.tune_rounded,
              size: 20,
              color: AppBrand.deepTeal,
            ),
          ),
        ),
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

  Widget _buildActiveDietaryFiltersRow(Set<String> tags) {
    String labelFor(String slug) {
      for (final o in DietaryOption.values) {
        if (o.slug == slug) return o.label;
      }
      return _titleCase(slug);
    }

    final sorted = tags.toList()..sort();
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Expanded(
          child: SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Row(
              children: [
                for (final tag in sorted)
                  Padding(
                    padding: const EdgeInsets.only(right: 8),
                    child: InputChip(
                      label: Text(labelFor(tag)),
                      visualDensity: VisualDensity.compact,
                      materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                      onDeleted: () => ref
                          .read(discoverSelectedDietaryTagsProvider.notifier)
                          .removeTag(tag),
                    ),
                  ),
              ],
            ),
          ),
        ),
        TextButton(
          onPressed: () => ref
              .read(discoverSelectedDietaryTagsProvider.notifier)
              .clearAll(),
          child: const Text('Clear all'),
        ),
      ],
    );
  }

  Widget _buildSearchOnly({required bool isSearchActive}) {
    return TextField(
      controller: _searchController,
      onChanged: (value) {
        ref.read(discoverSearchQueryProvider.notifier).state = value;
      },
      decoration: InputDecoration(
        prefixIcon: const Icon(Icons.search_rounded),
        hintText: 'Search recipes',
        isDense: true,
        suffixIcon: isSearchActive
            ? IconButton(
                tooltip: 'Clear search',
                onPressed: _clearDiscoverSearch,
                icon: const Icon(Icons.clear_rounded),
              )
            : null,
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
    final userId = ref.watch(currentUserProvider)?.id;
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
                              _discoverSaveAffordance(
                                context: context,
                                recipe: recipe,
                                savedRecipes: savedRecipes,
                                userId: userId,
                                onOpenSheet: () =>
                                    _showSaveDestinationModal(recipe),
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
      data: (tiles) {
        if (tiles.isEmpty) {
          return Padding(
            padding: const EdgeInsets.symmetric(vertical: 24),
            child: Column(
              children: [
                Text(
                  'No categories match your current filters',
                  style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                        color: Colors.grey[600],
                      ),
                ),
                const SizedBox(height: 12),
                FilledButton.tonal(
                  onPressed: () {
                    ref
                        .read(discoverSelectedDietaryTagsProvider.notifier)
                        .clearAll();
                  },
                  child: const Text('Clear dietary filters'),
                ),
                const SizedBox(height: 8),
                TextButton(
                  onPressed: () => context.push('/profile'),
                  child: const Text('Adjust in Profile'),
                ),
              ],
            ),
          );
        }
        return GridView.builder(
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
            graphicUrl: browseCategoryById(tile.id)?.graphicUrl ??
                _cuisineGraphicForLabel(tile.label),
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
      );
      },
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
        builder: (_) => _DiscoverRecipeDetailPage(
          recipe: recipe,
          onSaveTo: _showSaveDestinationModal,
        ),
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
    final savedRecipes = ref.read(recipesProvider).valueOrNull ?? [];
    final user = ref.read(currentUserProvider);
    final hasSharedHousehold =
        ref.read(hasSharedHouseholdProvider).valueOrNull ?? false;
    final summary = _discoverSaveSummary(recipe, savedRecipes, user?.id);

    var saveToFavorites = summary.myFavorite;
    var saveToTry = summary.myToTry;
    var saveToHousehold = hasSharedHousehold && summary.onHousehold;
    var householdFavorite = summary.onHousehold
        ? summary.householdFavorite
        : summary.myFavorite;
    var householdToTry =
        summary.onHousehold ? summary.householdToTry : summary.myToTry;

    final shouldSave = await showModalBottomSheet<bool>(
      context: context,
      showDragHandle: true,
      builder: (context) => StatefulBuilder(
        builder: (context, setModalState) => SafeArea(
          child: SingleChildScrollView(
            padding: const EdgeInsets.fromLTRB(16, 4, 16, 16),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Save to…',
                  style: Theme.of(context).textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.w700,
                      ),
                ),
                const SizedBox(height: 12),
                Text(
                  'My Recipes',
                  style: Theme.of(context).textTheme.titleSmall?.copyWith(
                        fontWeight: FontWeight.w700,
                      ),
                ),
                const SizedBox(height: 4),
                SwitchListTile.adaptive(
                  contentPadding: EdgeInsets.zero,
                  secondary: const Icon(Icons.favorite_border_rounded),
                  title: const Text('Favorite'),
                  subtitle: const Text(
                    'Show under Favorites on My Recipes.',
                  ),
                  value: saveToFavorites,
                  onChanged: (value) {
                    setModalState(() => saveToFavorites = value);
                  },
                ),
                SwitchListTile.adaptive(
                  contentPadding: EdgeInsets.zero,
                  secondary: const Icon(Icons.bookmark_border_rounded),
                  title: const Text('To Try'),
                  subtitle: const Text(
                    'Show under To Try on My Recipes.',
                  ),
                  value: saveToTry,
                  onChanged: (value) {
                    setModalState(() => saveToTry = value);
                  },
                ),
                const SizedBox(height: 8),
                Text(
                  'Household',
                  style: Theme.of(context).textTheme.titleSmall?.copyWith(
                        fontWeight: FontWeight.w700,
                      ),
                ),
                const SizedBox(height: 4),
                if (!hasSharedHousehold)
                  ListTile(
                    contentPadding: EdgeInsets.zero,
                    leading: const Icon(Icons.home_outlined),
                    title: const Text('Share with household'),
                    subtitle: const Text(
                      'Create or join a household in Settings to share recipes.',
                    ),
                  )
                else ...[
                  SwitchListTile.adaptive(
                    contentPadding: EdgeInsets.zero,
                    secondary: const Icon(Icons.groups_2_outlined),
                    title: const Text('Save to Household'),
                    subtitle: const Text(
                      'Adds a copy everyone in your household can open.',
                    ),
                    value: saveToHousehold,
                    onChanged: (value) {
                      setModalState(() {
                        saveToHousehold = value;
                        if (value) {
                          householdFavorite = saveToFavorites;
                          householdToTry = saveToTry;
                        }
                      });
                    },
                  ),
                  if (saveToHousehold) ...[
                    SwitchListTile.adaptive(
                      contentPadding: EdgeInsets.zero,
                      secondary: const Icon(Icons.favorite_border_rounded),
                      title: const Text('Favorite on Household Recipes'),
                      value: householdFavorite,
                      onChanged: (value) {
                        setModalState(() => householdFavorite = value);
                      },
                    ),
                    SwitchListTile.adaptive(
                      contentPadding: EdgeInsets.zero,
                      secondary: const Icon(Icons.bookmark_border_rounded),
                      title: const Text('To Try on Household Recipes'),
                      value: householdToTry,
                      onChanged: (value) {
                        setModalState(() => householdToTry = value);
                      },
                    ),
                  ],
                ],
                const SizedBox(height: 12),
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
      householdFavorite: householdFavorite,
      householdToTry: householdToTry,
    );
  }

  Future<void> _saveRecipeToDestinations(
    Recipe recipe, {
    required bool saveToFavorites,
    required bool saveToTry,
    required bool saveToHousehold,
    bool householdFavorite = false,
    bool householdToTry = false,
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
              householdFavorite: householdFavorite,
              householdToTry: householdToTry,
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

  Future<void> _showFilterSheet() async {
    final initialDietary = ref.read(discoverSelectedDietaryTagsProvider);
    final initialMeal = ref.read(discoverMealTypeProvider);

    final draftDietary = {...initialDietary};
    var draftMeal = initialMeal;

    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
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
                            'Filters',
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
                                draftDietary.clear();
                                draftMeal = DiscoverMealType.sauce;
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
                        children: DietaryOption.values
                            .map(
                              (option) => FilterChip(
                                label: Text(option.label),
                                selected: draftDietary.contains(option.slug),
                                onSelected: (selected) {
                                  setModalState(() {
                                    if (selected) {
                                      draftDietary.add(option.slug);
                                    } else {
                                      draftDietary.remove(option.slug);
                                    }
                                  });
                                },
                              ),
                            )
                            .toList(),
                      ),
                      Padding(
                        padding: const EdgeInsets.only(top: 4),
                        child: GestureDetector(
                          onTap: () {
                            Navigator.pop(context);
                            context.push('/profile');
                          },
                          child: Text(
                            'Manage defaults in Profile',
                            style:
                                Theme.of(context).textTheme.bodySmall?.copyWith(
                                      color: AppBrand.deepTeal,
                                      decoration: TextDecoration.underline,
                                    ),
                          ),
                        ),
                      ),
                      sectionTitle('Meal Type'),
                      Wrap(
                        spacing: 8,
                        runSpacing: 8,
                        children: DiscoverMealType.values
                            .map(
                              (meal) => ChoiceChip(
                                label: Text(meal.label),
                                selected: draftMeal == meal,
                                onSelected: (_) =>
                                    setModalState(() => draftMeal = meal),
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
                                    .read(discoverSelectedDietaryTagsProvider
                                        .notifier)
                                    .setTags(draftDietary);
                                ref
                                    .read(discoverMealTypeProvider.notifier)
                                    .state = draftMeal;
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
    final recipesAsync = ref.watch(discoverDietaryFilteredPublicRecipesProvider);
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
                      final userId = ref.watch(currentUserProvider)?.id;
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
                                        _discoverSaveAffordance(
                                          context: context,
                                          recipe: recipe,
                                          savedRecipes: savedRecipes,
                                          userId: userId,
                                          onOpenSheet: () =>
                                              onSaveRecipe(recipe),
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
  final category = browseCategoryById(cuisineId);
  if (category == null) return false;
  final haystack =
      '${recipe.title} ${recipe.cuisineTags.join(' ')}'.toLowerCase();
  return category.keywords.any(haystack.contains);
}

bool _savedRecipeMatchesDiscover(Recipe discoverRecipe, Recipe saved) {
  final discoverSourceUrl = (discoverRecipe.sourceUrl ?? '').trim();
  final discoverApiId = (discoverRecipe.apiId ?? '').trim();
  final discoverTitle = discoverRecipe.title.trim().toLowerCase();
  final discoverMealType = discoverRecipe.mealType.name;

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
  return false;
}

/// First personal row matching [discoverRecipe] (URL, api id, or title+meal), in list order.
Recipe? _findPersonalSavedDiscoverRecipe(
  Recipe discoverRecipe,
  List<Recipe> savedRecipes,
) {
  for (final saved in savedRecipes) {
    if (saved.visibility != RecipeVisibility.personal) continue;
    if (_savedRecipeMatchesDiscover(discoverRecipe, saved)) return saved;
  }
  return null;
}

class _DiscoverSaveSummary {
  const _DiscoverSaveSummary({
    required this.personal,
    required this.householdCopy,
  });

  final Recipe? personal;
  final Recipe? householdCopy;

  bool get onHousehold => householdCopy != null;
  bool get myFavorite => personal?.isFavorite ?? false;
  bool get myToTry => personal?.isToTry ?? false;
  bool get householdFavorite => householdCopy?.isFavorite ?? false;
  bool get householdToTry => householdCopy?.isToTry ?? false;
  bool get hasPersonal => personal != null;
  bool get hasAnyDestination => hasPersonal || onHousehold;
}

_DiscoverSaveSummary _discoverSaveSummary(
  Recipe discoverRecipe,
  List<Recipe> savedRecipes,
  String? currentUserId,
) {
  final personal =
      _findPersonalSavedDiscoverRecipe(discoverRecipe, savedRecipes);
  final householdCopy = personal != null && currentUserId != null
      ? householdCopyRecipeForPersonal(
          personal: personal,
          allRecipes: savedRecipes,
          currentUserId: currentUserId,
        )
      : null;
  return _DiscoverSaveSummary(
    personal: personal,
    householdCopy: householdCopy,
  );
}

String _formatDiscoverSaveSummary(_DiscoverSaveSummary s) {
  if (!s.hasAnyDestination) return 'Not saved yet';
  final parts = <String>[];
  if (s.myFavorite) parts.add('Favorites');
  if (s.myToTry) parts.add('To Try');
  if (s.onHousehold) parts.add('Household');
  if (parts.isEmpty) return 'In My Recipes';
  return parts.join(' · ');
}

Widget _discoverSaveAffordance({
  required BuildContext context,
  required Recipe recipe,
  required List<Recipe> savedRecipes,
  required String? userId,
  required VoidCallback onOpenSheet,
}) {
  final summary = _discoverSaveSummary(recipe, savedRecipes, userId);
  const active = Color(0xFF2F6B46);
  const dim = Color(0xFF2D342F);
  final saved = summary.hasAnyDestination;
  return Material(
    color: const Color(0xFFC8D3C2).withValues(alpha: 0.9),
    borderRadius: BorderRadius.circular(10),
    child: InkWell(
      onTap: onOpenSheet,
      borderRadius: BorderRadius.circular(10),
      child: Padding(
        padding: const EdgeInsets.all(6),
        child: Icon(
          saved ? Icons.bookmark_rounded : Icons.bookmark_border_rounded,
          size: 18,
          color: saved ? active : dim,
        ),
      ),
    ),
  );
}

class _DiscoverRecipeDetailPage extends ConsumerStatefulWidget {
  const _DiscoverRecipeDetailPage({
    required this.recipe,
    required this.onSaveTo,
  });

  final Recipe recipe;
  final Future<void> Function(Recipe recipe) onSaveTo;

  @override
  ConsumerState<_DiscoverRecipeDetailPage> createState() =>
      _DiscoverRecipeDetailPageState();
}

class _DiscoverRecipeDetailPageState
    extends ConsumerState<_DiscoverRecipeDetailPage> {
  _DiscoverDetailSection _selectedSection = _DiscoverDetailSection.ingredients;

  @override
  Widget build(BuildContext context) {
    final recipe = widget.recipe;
    final savedRecipes = ref.watch(recipesProvider).valueOrNull ?? [];
    final user = ref.watch(currentUserProvider);
    final summary = _discoverSaveSummary(recipe, savedRecipes, user?.id);
    final subtitle = _formatDiscoverSaveSummary(summary);
    final titleLabel = summary.hasAnyDestination ? 'Saved' : 'Save to…';

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
        child: FilledButton(
          onPressed: () => widget.onSaveTo(recipe),
          style: FilledButton.styleFrom(
            minimumSize: const Size.fromHeight(52),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(14),
            ),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(
                    summary.hasAnyDestination
                        ? Icons.check_circle_outline_rounded
                        : Icons.library_add_check_rounded,
                    size: 20,
                  ),
                  const SizedBox(width: 8),
                  Text(
                    titleLabel,
                    style: const TextStyle(
                      fontWeight: FontWeight.w700,
                      fontSize: 16,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 2),
              Text(
                subtitle,
                style: TextStyle(
                  fontWeight: FontWeight.w500,
                  fontSize: 12,
                  color: Theme.of(context).colorScheme.onPrimary.withValues(
                        alpha: 0.92,
                      ),
                ),
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                textAlign: TextAlign.center,
              ),
            ],
          ),
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
