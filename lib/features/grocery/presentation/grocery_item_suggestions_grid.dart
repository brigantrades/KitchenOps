import 'package:collection/collection.dart';
import 'package:flutter/material.dart';
import 'package:plateplan/core/models/app_models.dart';
import 'package:plateplan/core/ui/food_icon_resolver.dart';
import 'package:plateplan/features/grocery/data/grocery_repository.dart';

const double kGroceryCardGridSpacing = 8;
const double kGroceryCardAspectRatio = 1.15;

/// Hides non-create suggestion chips whose label equals the typed query; always
/// keeps the create-new row (same label as query). Used by [GroceryItemSuggestionsGrid]
/// and tests.
List<({String label, bool isCreate})> filterGrocerySuggestionOptionsForDisplay({
  required List<({String label, bool isCreate})> suggestionOptions,
  required String normalizedTypedQuery,
}) {
  return suggestionOptions
      .where(
        (o) =>
            o.isCreate ||
            normalizeGroceryItemName(o.label) != normalizedTypedQuery,
      )
      .toList();
}

class GroceryItemSuggestionsGrid extends StatelessWidget {
  const GroceryItemSuggestionsGrid({
    super.key,
    required this.repo,
    required this.typedValue,
    required this.recentItems,
    required this.onPick,
    this.limit = 12,
    this.maxHeight = 230,
    this.duplicateMessage,
  });

  final GroceryRepository repo;
  final String typedValue;
  final List<GroceryItem> recentItems;
  final ValueChanged<String> onPick;
  final int limit;
  final double maxHeight;
  final String? duplicateMessage;

  IconData _categoryIcon(GroceryCategory category) {
    return switch (category) {
      GroceryCategory.produce => Icons.eco_rounded,
      GroceryCategory.meatFish => Icons.set_meal_rounded,
      GroceryCategory.dairyEggs => Icons.egg_alt_rounded,
      GroceryCategory.pantryGrains => Icons.rice_bowl_rounded,
      GroceryCategory.bakery => Icons.bakery_dining_rounded,
      GroceryCategory.other => Icons.shopping_bag_rounded,
    };
  }

  @override
  Widget build(BuildContext context) {
    final typedQuery = typedValue.trim();
    // No cards until the user has typed at least 2 characters (same threshold
    // as grocery search; avoids the empty-query staple list in [suggestItems]).
    if (typedQuery.length < 2) {
      return const SizedBox.shrink();
    }

    final suggestions = repo.suggestItems(
      query: typedQuery,
      recentItems: recentItems,
      limit: limit,
    );
    final existingNames = recentItems
        .map((item) => normalizeGroceryItemName(item.name))
        .where((name) => name.isNotEmpty)
        .toSet();
    final normalizedTypedQuery = normalizeGroceryItemName(typedQuery);
    final hasExactSuggestion = suggestions.any(
      (entry) => normalizeGroceryItemName(entry) == normalizedTypedQuery,
    );
    final hasExactExisting = existingNames.contains(normalizedTypedQuery);
    final suggestionOptions = <({String label, bool isCreate})>[
      if (typedQuery.isNotEmpty && !hasExactSuggestion && !hasExactExisting)
        (label: typedQuery, isCreate: true),
      ...suggestions.map((entry) => (label: entry, isCreate: false)),
    ].take(limit).toList();
    final filteredOptions = filterGrocerySuggestionOptionsForDisplay(
      suggestionOptions: suggestionOptions,
      normalizedTypedQuery: normalizedTypedQuery,
    );
    if (filteredOptions.isEmpty) return const SizedBox.shrink();

    return ConstrainedBox(
      constraints: BoxConstraints(maxHeight: maxHeight),
      child: LayoutBuilder(
        builder: (context, constraints) {
          final crossAxisCount = constraints.maxWidth < 360 ? 2 : 3;
          return GridView.builder(
            primary: false,
            shrinkWrap: true,
            itemCount: filteredOptions.length,
            gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
              crossAxisCount: crossAxisCount,
              mainAxisSpacing: kGroceryCardGridSpacing,
              crossAxisSpacing: kGroceryCardGridSpacing,
              childAspectRatio: kGroceryCardAspectRatio,
            ),
            itemBuilder: (context, index) {
              final option = filteredOptions[index];
              final suggestion = option.label;
              final isCreateOption = option.isCreate;
              final suggestionCategory = repo.categorize(suggestion);
              final isAlreadyInBasket = existingNames.contains(
                normalizeGroceryItemName(suggestion),
              );
              final suggestionAsset = foodIconAssetForName(
                suggestion,
                category: suggestionCategory,
              );
              return Material(
                color: isAlreadyInBasket
                    ? const Color(0xFFE8F7EE)
                    : const Color(0xFFF0F7FF),
                borderRadius: BorderRadius.circular(12),
                child: InkWell(
                  borderRadius: BorderRadius.circular(12),
                  onTap: () {
                    final existing = recentItems.firstWhereOrNull(
                      (item) =>
                          normalizeGroceryItemName(item.name) ==
                          normalizeGroceryItemName(suggestion),
                    );
                    if (existing != null) {
                      if (duplicateMessage != null && duplicateMessage!.isNotEmpty) {
                        ScaffoldMessenger.of(context).showSnackBar(
                          SnackBar(content: Text(duplicateMessage!)),
                        );
                      }
                      return;
                    }
                    onPick(suggestion);
                  },
                  child: Padding(
                    padding: const EdgeInsets.all(8),
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        if (isCreateOption)
                          const Icon(
                            Icons.add_circle_rounded,
                            size: 24,
                            color: Color(0xFF3B74A8),
                          )
                        else if (suggestionAsset != null)
                          Image.asset(
                            suggestionAsset,
                            width: 38,
                            height: 38,
                            filterQuality: FilterQuality.high,
                            errorBuilder: (context, error, stackTrace) {
                              return Icon(
                                _categoryIcon(suggestionCategory),
                                size: 38,
                                color: isAlreadyInBasket
                                    ? const Color(0xFF2F8B57)
                                    : const Color(0xFF3B74A8),
                              );
                            },
                          )
                        else
                          Icon(
                            _categoryIcon(suggestionCategory),
                            size: 38,
                            color: isAlreadyInBasket
                                ? const Color(0xFF2F8B57)
                                : const Color(0xFF3B74A8),
                          ),
                        const SizedBox(height: 6),
                        Text(
                          suggestion,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          textAlign: TextAlign.center,
                          style: TextStyle(
                            fontSize: 12,
                            color: isAlreadyInBasket ? const Color(0xFF1D5E39) : null,
                            fontWeight: FontWeight.w600,
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
      ),
    );
  }
}
