import 'dart:async';

import 'package:collection/collection.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:plateplan/core/models/app_models.dart';
import 'package:plateplan/core/ui/food_icon_resolver.dart';
import 'package:plateplan/core/ui/hero_panel.dart';
import 'package:plateplan/core/ui/recipo_kit.dart';
import 'package:plateplan/core/ui/section_card.dart';
import 'package:plateplan/features/auth/data/auth_providers.dart';
import 'package:plateplan/features/grocery/data/grocery_repository.dart';

const double _groceryCardGridSpacing = 8;
const double _groceryCardAspectRatio = 1.15;

class GroceryScreen extends ConsumerStatefulWidget {
  const GroceryScreen({super.key});

  @override
  ConsumerState<GroceryScreen> createState() => _GroceryScreenState();
}

class _GroceryScreenState extends ConsumerState<GroceryScreen> {
  bool _addSheetOpen = false;

  @override
  void initState() {
    super.initState();
    // Warm up catalog in background to avoid blocking when opening the add sheet.
    unawaited(ref.read(groceryRepositoryProvider).ensureCatalogLoaded());
  }

  Future<void> _removeItem(String itemId) async {
    await ref.read(groceryRepositoryProvider).removeItem(itemId);
    ref.invalidate(groceryItemsProvider);
  }

  Future<void> _openAddItemSheet(List<GroceryItem> currentItems) async {
    final user = ref.read(currentUserProvider);
    if (user == null) {
      return;
    }
    final repo = ref.read(groceryRepositoryProvider);
    setState(() {
      _addSheetOpen = true;
    });
    final draftItem = await showModalBottomSheet<_PendingGroceryItem>(
      context: context,
      isScrollControlled: true,
      builder: (context) => _AddGroceryItemSheet(
        repo: repo,
        currentItems: currentItems,
      ),
    );
    if (!mounted || draftItem == null) {
      if (mounted) {
        setState(() {
          _addSheetOpen = false;
        });
      }
      return;
    }
    final matchedExisting = currentItems.firstWhereOrNull(
      (item) =>
          _normalizedItemName(item.name) == _normalizedItemName(draftItem.name),
    );
    if (matchedExisting != null) {
      setState(() {
        _addSheetOpen = false;
      });
      if (!mounted) {
        return;
      }
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'Item already in basket. Long-press it in the list to update quantity.',
          ),
        ),
      );
      return;
    }
    try {
      await repo.addItem(
        userId: user.id,
        name: draftItem.name,
        quantity: draftItem.quantity,
      );
    } catch (_) {
      if (mounted) {
        setState(() {
          _addSheetOpen = false;
        });
      }
      if (!mounted) {
        return;
      }
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Could not add item. Check connection and try again.'),
        ),
      );
      return;
    }
    if (!mounted) {
      return;
    }
    setState(() {
      _addSheetOpen = false;
    });
    ref.invalidate(groceryItemsProvider);
  }

  Future<void> _clearAll() async {
    final user = ref.read(currentUserProvider);
    if (user == null) {
      return;
    }
    final confirmed = await showModalBottomSheet<bool>(
      context: context,
      showDragHandle: true,
      builder: (context) => BrandedSheetScaffold(
        title: 'Clear grocery list?',
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('This will remove all grocery items.'),
            const SizedBox(height: 12),
            Row(
              children: [
                Expanded(
                  child: FilledButton.tonal(
                    onPressed: () => Navigator.of(context).pop(false),
                    child: const Text('Cancel'),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: FilledButton(
                    onPressed: () => Navigator.of(context).pop(true),
                    child: const Text('Clear all'),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
    if (confirmed != true) {
      return;
    }
    await ref.read(groceryRepositoryProvider).clear(user.id);
    ref.invalidate(groceryItemsProvider);
  }

  Future<void> _promptUpdateQuantity(GroceryItem item) async {
    final qtyCtrl = TextEditingController(
      text: _displayQuantity(_safeQuantity(item.quantity, fallback: 1)),
    );
    final nextQuantity = await showModalBottomSheet<String>(
      context: context,
      showDragHandle: true,
      isScrollControlled: true,
      builder: (context) {
        return StatefulBuilder(
          builder: (context, setModalState) {
            final current = _safeQuantity(qtyCtrl.text, fallback: 1);
            return Padding(
              padding: EdgeInsets.fromLTRB(
                16,
                8,
                16,
                MediaQuery.of(context).viewInsets.bottom + 16,
              ),
              child: BrandedSheetScaffold(
                title: 'Update quantity',
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      item.name,
                      style: Theme.of(context).textTheme.titleMedium?.copyWith(
                            fontWeight: FontWeight.w700,
                          ),
                    ),
                    const SizedBox(height: 10),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        IconButton.filledTonal(
                          onPressed: () {
                            final next = (current - 1).clamp(1, 999);
                            qtyCtrl.text = _displayQuantity(next.toDouble());
                            setModalState(() {});
                          },
                          icon: const Icon(Icons.remove_rounded),
                        ),
                        const SizedBox(width: 8),
                        SizedBox(
                          width: 92,
                          child: TextField(
                            controller: qtyCtrl,
                            textAlign: TextAlign.center,
                            keyboardType: const TextInputType.numberWithOptions(
                              decimal: true,
                            ),
                            onChanged: (_) => setModalState(() {}),
                            decoration: const InputDecoration(
                              labelText: 'Qty',
                              isDense: true,
                            ),
                          ),
                        ),
                        const SizedBox(width: 8),
                        IconButton.filledTonal(
                          onPressed: () {
                            final next = (current + 1).clamp(1, 999);
                            qtyCtrl.text = _displayQuantity(next.toDouble());
                            setModalState(() {});
                          },
                          icon: const Icon(Icons.add_rounded),
                        ),
                      ],
                    ),
                    const SizedBox(height: 12),
                    SizedBox(
                      width: double.infinity,
                      child: FilledButton(
                        onPressed: () {
                          final quantity = _displayQuantity(
                            _safeQuantity(qtyCtrl.text, fallback: 1),
                          );
                          Navigator.of(context).pop(quantity);
                        },
                        child: const Text('Save quantity'),
                      ),
                    ),
                  ],
                ),
              ),
            );
          },
        );
      },
    );
    qtyCtrl.dispose();
    if (!mounted || nextQuantity == null) {
      return;
    }
    try {
      await ref
          .read(groceryRepositoryProvider)
          .updateItemQuantity(item.id, nextQuantity);
      ref.invalidate(groceryItemsProvider);
      if (!mounted) {
        return;
      }
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Updated ${item.name} quantity')),
      );
    } catch (_) {
      if (!mounted) {
        return;
      }
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Could not update quantity right now.')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final itemsAsync = ref.watch(groceryItemsProvider);

    return Scaffold(
      resizeToAvoidBottomInset: false,
      appBar: AppBar(
        title: const Text('Grocery List'),
        actions: [
          IconButton(
            icon: const Icon(Icons.share_outlined),
            onPressed: () async {
              final messenger = ScaffoldMessenger.of(context);
              final items = await ref.read(groceryItemsProvider.future);
              await ref.read(groceryRepositoryProvider).shareText(items);
              if (!mounted) {
                return;
              }
              messenger.showSnackBar(
                const SnackBar(content: Text('Copied list to clipboard')),
              );
            },
          ),
          IconButton(
            icon: const Icon(Icons.delete_sweep_outlined),
            onPressed: _clearAll,
          ),
        ],
      ),
      floatingActionButtonLocation: FloatingActionButtonLocation.centerFloat,
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => _openAddItemSheet(itemsAsync.valueOrNull ?? const []),
        icon: const Icon(Icons.add_rounded),
        label: const Text('Add item'),
      ),
      body: itemsAsync.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (error, _) => Center(child: Text('Error: $error')),
        data: (items) {
          final plannerCount = items.where((e) => e.fromPlanner).length;

          return ListView(
            padding: const EdgeInsets.fromLTRB(12, 10, 12, 96),
            children: [
              HeroPanel(
                child: Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.all(10),
                      decoration: BoxDecoration(
                        color: Colors.white.withValues(alpha: 0.8),
                        borderRadius: BorderRadius.circular(14),
                      ),
                      child: const Icon(Icons.shopping_cart_rounded),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Text(
                        '${items.length} items • $plannerCount from planner',
                        style:
                            Theme.of(context).textTheme.titleMedium?.copyWith(
                                  fontWeight: FontWeight.w700,
                                ),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 12),
              const SizedBox(height: 4),
              if (_addSheetOpen)
                SectionCard(
                  child: Padding(
                    padding: const EdgeInsets.all(8),
                    child: Row(
                      children: [
                        const Icon(Icons.edit_note_rounded),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            'Adding item... Long-press in list to edit quantity later.',
                            style: Theme.of(context).textTheme.bodyMedium,
                          ),
                        ),
                      ],
                    ),
                  ),
                )
              else if (items.isEmpty)
                SectionCard(
                  child: Padding(
                    padding: const EdgeInsets.all(6),
                    child: Column(
                      children: [
                        const Icon(Icons.shopping_basket_outlined, size: 34),
                        const SizedBox(height: 8),
                        Text(
                          'No items yet',
                          style: Theme.of(context).textTheme.titleMedium,
                        ),
                        const SizedBox(height: 4),
                        const Text(
                            'Tap "Add item" at the bottom to start your list.'),
                      ],
                    ),
                  ),
                )
              else
                SectionCard(
                  child: LayoutBuilder(
                    builder: (context, constraints) {
                      const crossAxisCount = 3;
                      return GridView.builder(
                        shrinkWrap: true,
                        physics: const NeverScrollableScrollPhysics(),
                        itemCount: items.length,
                        gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                          crossAxisCount: crossAxisCount,
                          mainAxisSpacing: _groceryCardGridSpacing,
                          crossAxisSpacing: _groceryCardGridSpacing,
                          childAspectRatio: _groceryCardAspectRatio,
                        ),
                        itemBuilder: (context, index) {
                          return _GroceryItemCard(
                            item: items[index],
                            onRemove: _removeItem,
                            onUpdateQuantity: _promptUpdateQuantity,
                          );
                        },
                      );
                    },
                  ),
                ),
            ],
          );
        },
      ),
    );
  }
}

class _PendingGroceryItem {
  const _PendingGroceryItem({
    required this.name,
    required this.quantity,
  });

  final String name;
  final String quantity;
}

class _AddGroceryItemSheet extends StatefulWidget {
  const _AddGroceryItemSheet({
    required this.repo,
    required this.currentItems,
  });

  final GroceryRepository repo;
  final List<GroceryItem> currentItems;

  @override
  State<_AddGroceryItemSheet> createState() => _AddGroceryItemSheetState();
}

class _AddGroceryItemSheetState extends State<_AddGroceryItemSheet> {
  late final TextEditingController _nameCtrl;
  late final TextEditingController _qtyCtrl;
  late final FocusNode _searchFocusNode;
  Timer? _searchDebounce;
  String _debouncedQuery = '';

  @override
  void initState() {
    super.initState();
    _nameCtrl = TextEditingController();
    _qtyCtrl = TextEditingController(text: '1');
    _searchFocusNode = FocusNode(debugLabel: 'grocery_search');
    _nameCtrl.addListener(_onNameChanged);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      _searchFocusNode.requestFocus();
      _searchDebounce?.cancel();
      _searchDebounce = Timer(const Duration(milliseconds: 220), () {
        if (!mounted || _searchFocusNode.hasFocus) return;
        _searchFocusNode.requestFocus();
      });
    });
  }

  void _onNameChanged() {
    _searchDebounce?.cancel();
    _searchDebounce = Timer(const Duration(milliseconds: 140), () {
      if (!mounted) return;
      setState(() {
        _debouncedQuery = _nameCtrl.text;
      });
    });
  }

  @override
  void dispose() {
    _searchDebounce?.cancel();
    _nameCtrl.removeListener(_onNameChanged);
    _searchFocusNode.dispose();
    _nameCtrl.dispose();
    _qtyCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final queryForSuggestions =
        _debouncedQuery.trim().length < 2 ? '' : _debouncedQuery;
    final suggestions = widget.repo.suggestItems(
      query: queryForSuggestions,
      recentItems: widget.currentItems,
      limit: 12,
    );
    final existingNames = widget.currentItems
        .map((item) => _normalizedItemName(item.name))
        .where((name) => name.isNotEmpty)
        .toSet();
    final typedQuery = _nameCtrl.text.trim();
    final normalizedTypedQuery = _normalizedItemName(typedQuery);
    final hasExactSuggestion = suggestions.any(
      (entry) => _normalizedItemName(entry) == normalizedTypedQuery,
    );
    final hasExactExisting = existingNames.contains(normalizedTypedQuery);
    final suggestionOptions = <({String label, bool isCreate})>[
      if (typedQuery.isNotEmpty && !hasExactSuggestion && !hasExactExisting)
        (label: typedQuery, isCreate: true),
      ...suggestions.map((entry) => (label: entry, isCreate: false)),
    ].take(12).toList();
    final media = MediaQuery.of(context);
    final maxSheetHeight = media.size.height * 0.82;
    return SafeArea(
      top: false,
      child: AnimatedPadding(
        duration: const Duration(milliseconds: 160),
        curve: Curves.easeOut,
        padding: EdgeInsets.fromLTRB(12, 12, 12, media.viewInsets.bottom + 12),
        child: ConstrainedBox(
          constraints: BoxConstraints(maxHeight: maxSheetHeight),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Add item',
                style: Theme.of(context).textTheme.titleLarge?.copyWith(
                      fontWeight: FontWeight.w700,
                    ),
              ),
              const SizedBox(height: 12),
              Expanded(
                child: SingleChildScrollView(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      TextField(
                        controller: _nameCtrl,
                        focusNode: _searchFocusNode,
                        autofocus: false,
                        textInputAction: TextInputAction.search,
                        onChanged: (_) {
                          // Keep button state responsive while suggestion updates are debounced.
                          setState(() {});
                        },
                        decoration: const InputDecoration(
                          hintText: 'Search or type item',
                          prefixIcon: Icon(Icons.search_rounded),
                        ),
                      ),
                      const SizedBox(height: 8),
                      TextField(
                        controller: _qtyCtrl,
                        keyboardType: TextInputType.number,
                        onChanged: (_) => setState(() {}),
                        decoration: const InputDecoration(
                          labelText: 'Quantity',
                        ),
                      ),
                      const SizedBox(height: 10),
                      if (suggestionOptions.isNotEmpty)
                        ConstrainedBox(
                          constraints: const BoxConstraints(maxHeight: 230),
                          child: LayoutBuilder(
                            builder: (context, constraints) {
                              final crossAxisCount =
                                  constraints.maxWidth < 360 ? 2 : 3;
                              return GridView.builder(
                                primary: false,
                                shrinkWrap: true,
                                itemCount: suggestionOptions.length,
                                gridDelegate:
                                    SliverGridDelegateWithFixedCrossAxisCount(
                                  crossAxisCount: crossAxisCount,
                                  mainAxisSpacing: _groceryCardGridSpacing,
                                  crossAxisSpacing: _groceryCardGridSpacing,
                                  childAspectRatio: _groceryCardAspectRatio,
                                ),
                                itemBuilder: (context, index) {
                                  final option = suggestionOptions[index];
                                  final suggestion = option.label;
                                  final isCreateOption = option.isCreate;
                                  final suggestionCategory =
                                      widget.repo.categorize(suggestion);
                                  final isAlreadyInBasket =
                                      existingNames.contains(
                                    _normalizedItemName(suggestion),
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
                                        final existing =
                                            widget.currentItems.firstWhereOrNull(
                                          (item) =>
                                              _normalizedItemName(item.name) ==
                                              _normalizedItemName(suggestion),
                                        );
                                        if (existing != null) {
                                          ScaffoldMessenger.of(context)
                                              .showSnackBar(
                                            const SnackBar(
                                              content: Text(
                                                'Already in basket. Long-press it in your list to edit quantity.',
                                              ),
                                            ),
                                          );
                                          return;
                                        }
                                        FocusManager.instance.primaryFocus
                                            ?.unfocus();
                                        final quantity = _displayQuantity(
                                          _safeQuantity(
                                            _qtyCtrl.text,
                                            fallback: 1,
                                          ),
                                        );
                                        Navigator.of(context).pop(
                                          _PendingGroceryItem(
                                            name: suggestion,
                                            quantity: quantity,
                                          ),
                                        );
                                      },
                                      child: Padding(
                                        padding: const EdgeInsets.all(8),
                                        child: Column(
                                          mainAxisAlignment:
                                              MainAxisAlignment.center,
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
                                                filterQuality:
                                                    FilterQuality.high,
                                                errorBuilder: (context, error,
                                                    stackTrace) {
                                                  return Icon(
                                                    _iconForName(
                                                      suggestion,
                                                      fallback:
                                                          suggestionCategory
                                                              .icon,
                                                    ),
                                                    size: 38,
                                                    color: isAlreadyInBasket
                                                        ? const Color(
                                                            0xFF2F8B57)
                                                        : const Color(
                                                            0xFF3B74A8),
                                                  );
                                                },
                                              )
                                            else
                                              Icon(
                                                _iconForName(
                                                  suggestion,
                                                  fallback:
                                                      suggestionCategory.icon,
                                                ),
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
                                                color: isAlreadyInBasket
                                                    ? const Color(0xFF1D5E39)
                                                    : null,
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
                        ),
                      const SizedBox(height: 12),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 8),
              SizedBox(
                width: double.infinity,
                child: FilledButton(
                  onPressed: _nameCtrl.text.trim().isEmpty
                      ? null
                      : () {
                          FocusManager.instance.primaryFocus?.unfocus();
                          final name = _nameCtrl.text.trim();
                          final quantity = _displayQuantity(
                            _safeQuantity(_qtyCtrl.text, fallback: 1),
                          );
                          Navigator.of(context).pop(
                            _PendingGroceryItem(
                              name: name,
                              quantity: quantity,
                            ),
                          );
                        },
                  child: const Text('Add to grocery list'),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

}

class _GroceryItemCard extends StatelessWidget {
  const _GroceryItemCard({
    required this.item,
    required this.onRemove,
    required this.onUpdateQuantity,
  });

  final GroceryItem item;
  final Future<void> Function(String itemId) onRemove;
  final Future<void> Function(GroceryItem item) onUpdateQuantity;

  @override
  Widget build(BuildContext context) {
    final quantityValue = _safeQuantity(item.quantity, fallback: 1);
    final hasMultipleQuantity = quantityValue > 1;
    final quantityLabel = item.unit == null || item.unit!.trim().isEmpty
        ? _displayQuantity(quantityValue)
        : '${_displayQuantity(quantityValue)} ${item.unit!.trim()}';
    final scheme = Theme.of(context).colorScheme;
    final foodAsset = foodIconAssetForName(item.name, category: item.category);
    return Material(
      color: scheme.surfaceContainerHighest,
      borderRadius: BorderRadius.circular(16),
      child: InkWell(
        borderRadius: BorderRadius.circular(16),
        onTap: () => onRemove(item.id),
        onLongPress: () => onUpdateQuantity(item),
        child: LayoutBuilder(
          builder: (context, constraints) {
            final availableHeight = constraints.maxHeight - 20;
            final ultraCompact = availableHeight < 126;
            final compact = availableHeight < 150;
            const iconSize = 38.0;
            return Padding(
              padding: EdgeInsets.symmetric(
                horizontal: 8,
                vertical: ultraCompact ? 5 : (compact ? 7 : 10),
              ),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  if (foodAsset != null)
                    Image.asset(
                      foodAsset,
                      width: iconSize,
                      height: iconSize,
                      filterQuality: FilterQuality.high,
                      errorBuilder: (context, error, stackTrace) {
                        return Icon(
                          _iconForName(
                            item.name,
                            fallback: item.category.icon,
                          ),
                          color: item.category.tint,
                          size: iconSize,
                        );
                      },
                    )
                  else
                    Icon(
                      _iconForName(item.name, fallback: item.category.icon),
                      color: item.category.tint,
                      size: iconSize,
                    ),
                  SizedBox(height: ultraCompact ? 4 : (compact ? 6 : 8)),
                  Text(
                    item.name,
                    maxLines: compact ? 1 : 2,
                    overflow: TextOverflow.ellipsis,
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      color: scheme.onSurface,
                      fontWeight: FontWeight.w600,
                      fontSize: ultraCompact ? 12 : 12,
                    ),
                  ),
                  if (ultraCompact && hasMultipleQuantity) ...[
                    const SizedBox(height: 2),
                    Text(
                      '(${_displayQuantity(quantityValue)})',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        color: scheme.onSurface.withValues(alpha: 0.78),
                        fontSize: 11,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ],
                  if (hasMultipleQuantity && !ultraCompact) ...[
                    SizedBox(height: compact ? 2 : 4),
                    Container(
                      padding: EdgeInsets.symmetric(
                        horizontal: compact ? 7 : 8,
                        vertical: compact ? 2 : 4,
                      ),
                      decoration: BoxDecoration(
                        color: scheme.primaryContainer,
                        borderRadius: BorderRadius.circular(999),
                      ),
                      child: Text(
                        quantityLabel,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        textAlign: TextAlign.center,
                        style: TextStyle(
                          color: scheme.onSurface,
                          fontSize: compact ? 10 : 12,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                    ),
                  ],
                  if (item.fromPlanner && !compact) ...[
                    const SizedBox(height: 6),
                    Icon(
                      Icons.auto_awesome_rounded,
                      size: 16,
                      color: scheme.secondary,
                    ),
                  ],
                ],
              ),
            );
          },
        ),
      ),
    );
  }
}

IconData _iconForName(String name, {required IconData fallback}) {
  final lower = name.toLowerCase();
  if (lower.contains('milk')) return Icons.local_drink_rounded;
  if (lower.contains('banana')) return Icons.energy_savings_leaf_rounded;
  if (lower.contains('strawberr')) return Icons.local_florist_rounded;
  if (lower.contains('bread')) return Icons.bakery_dining_rounded;
  if (lower.contains('jam')) return Icons.breakfast_dining_rounded;
  if (lower.contains('juice')) return Icons.local_bar_rounded;
  if (lower.contains('potato')) return Icons.circle_rounded;
  if (lower.contains('carrot')) return Icons.grass_rounded;
  if (lower.contains('apple')) return Icons.apple_rounded;
  if (lower.contains('egg')) return Icons.egg_alt_rounded;
  return fallback;
}

String _normalizedItemName(String value) {
  return value
      .trim()
      .toLowerCase()
      .replaceAll(RegExp(r'\s+'), ' ');
}

double _safeQuantity(String? raw, {required double fallback}) {
  final normalized = raw?.trim().replaceAll(',', '.');
  final parsed = normalized == null ? null : double.tryParse(normalized);
  if (parsed == null || parsed <= 0) return fallback;
  return parsed;
}

String _displayQuantity(double value) {
  if (value == value.roundToDouble()) {
    return value.toInt().toString();
  }
  return value.toStringAsFixed(1);
}

extension on GroceryCategory {
  IconData get icon => switch (this) {
        GroceryCategory.produce => Icons.eco_rounded,
        GroceryCategory.meatFish => Icons.set_meal_rounded,
        GroceryCategory.dairyEggs => Icons.egg_alt_rounded,
        GroceryCategory.pantryGrains => Icons.rice_bowl_rounded,
        GroceryCategory.bakery => Icons.bakery_dining_rounded,
        GroceryCategory.other => Icons.shopping_bag_rounded,
      };

  Color get tint => switch (this) {
        GroceryCategory.produce => const Color(0xFF37A852),
        GroceryCategory.meatFish => const Color(0xFFEE6A63),
        GroceryCategory.dairyEggs => const Color(0xFFE9A100),
        GroceryCategory.pantryGrains => const Color(0xFF6F8BD9),
        GroceryCategory.bakery => const Color(0xFFBD7E52),
        GroceryCategory.other => const Color(0xFF7A8798),
      };
}
