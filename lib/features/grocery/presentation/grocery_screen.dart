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
import 'package:plateplan/features/household/data/household_providers.dart';
import 'package:plateplan/features/profile/data/profile_providers.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

const double _groceryCardGridSpacing = 8;
const double _groceryCardAspectRatio = 1.15;

class GroceryScreen extends ConsumerStatefulWidget {
  const GroceryScreen({super.key});

  @override
  ConsumerState<GroceryScreen> createState() => _GroceryScreenState();
}

class _GroceryScreenState extends ConsumerState<GroceryScreen> {
  bool _addSheetOpen = false;
  int _listScopeIndex = 0;

  @override
  void initState() {
    super.initState();
    // Warm up catalog in background to avoid blocking when opening the add sheet.
    unawaited(ref.read(groceryRepositoryProvider).ensureCatalogLoaded());
  }

  Future<void> _removeItem(GroceryItem item) async {
    await ref.read(groceryRecentsProvider.notifier).recordRemovedItem(item);
    await ref.read(groceryRepositoryProvider).removeItem(item.id);
    ref.invalidate(groceryItemsProvider);
  }

  Future<void> _addFromRecent(
    RecentGroceryEntry entry,
    List<GroceryItem> currentItems,
  ) async {
    final user = ref.read(currentUserProvider);
    if (user == null) {
      return;
    }
    if (currentItems.any(
      (item) =>
          normalizeGroceryItemName(item.name) ==
          normalizeGroceryItemName(entry.name),
    )) {
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
    final repo = ref.read(groceryRepositoryProvider);
    try {
      await repo.addItem(
        userId: user.id,
        listId: ref.read(selectedListIdProvider),
        name: entry.name,
        quantity: entry.quantity?.trim().isNotEmpty == true
            ? entry.quantity
            : '1',
        unit: entry.unit,
        category: entry.category,
      );
    } on StateError catch (error) {
      if (!mounted) {
        return;
      }
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(error.message)),
      );
      return;
    } on PostgrestException catch (error) {
      if (!mounted) {
        return;
      }
      final message = error.message.toLowerCase();
      final friendly = message.contains('row-level security') ||
              message.contains('violates row-level')
          ? 'Your account is not an active household member yet. Open Profile and accept the household invite.'
          : 'Could not add item right now. Please try again.';
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(friendly)),
      );
      return;
    } catch (_) {
      if (!mounted) {
        return;
      }
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Could not add item right now. Please try again.'),
        ),
      );
      return;
    }
    if (!mounted) {
      return;
    }
    ref.invalidate(groceryItemsProvider);
    ref.invalidate(groceryRecentsProvider);
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
      useSafeArea: true,
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
          normalizeGroceryItemName(item.name) ==
          normalizeGroceryItemName(draftItem.name),
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
      final selectedListId = ref.read(selectedListIdProvider);
      await repo.addItem(
        userId: user.id,
        listId: selectedListId,
        name: draftItem.name,
        quantity: draftItem.quantity,
      );
    } on StateError catch (error) {
      if (mounted) {
        setState(() {
          _addSheetOpen = false;
        });
      }
      if (!mounted) {
        return;
      }
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(error.message)),
      );
      return;
    } on PostgrestException catch (error) {
      if (mounted) {
        setState(() {
          _addSheetOpen = false;
        });
      }
      if (!mounted) {
        return;
      }
      final message = error.message.toLowerCase();
      final friendly = message.contains('row-level security') ||
              message.contains('violates row-level')
          ? 'Your account is not an active household member yet. Open Profile and accept the household invite.'
          : 'Could not add item right now. Please try again.';
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(friendly)),
      );
      return;
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
          content: Text('Could not add item right now. Please try again.'),
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
    ref.invalidate(groceryRecentsProvider);
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
    await ref.read(groceryRepositoryProvider).clear(
          user.id,
          listId: ref.read(selectedListIdProvider),
        );
    ref.invalidate(groceryItemsProvider);
  }

  Future<void> _openReorderListSheet({
    required List<AppList> orderedLists,
    required ListScope scope,
  }) async {
    final user = ref.read(currentUserProvider);
    if (user == null || orderedLists.isEmpty) return;
    final profileRepo = ref.read(profileRepositoryProvider);
    var working = List<AppList>.from(orderedLists);
    var liveOrder = ref.read(profileProvider).valueOrNull?.groceryListOrder ??
        GroceryListOrder.empty;
    if (!mounted) return;
    await showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      isScrollControlled: true,
      useSafeArea: true,
      builder: (sheetCtx) {
        return StatefulBuilder(
          builder: (ctx, setModalState) {
            return Padding(
              padding: const EdgeInsets.fromLTRB(20, 0, 20, 20),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Text(
                    'List order',
                    style: Theme.of(ctx).textTheme.titleLarge?.copyWith(
                          fontWeight: FontWeight.w700,
                        ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    working.length > 1
                        ? 'Drag the grip to reorder. The top list opens first. Use the trash icon to delete a list.'
                        : 'Use the trash icon to delete this list.',
                    style: Theme.of(ctx).textTheme.bodyMedium,
                  ),
                  const SizedBox(height: 12),
                  SizedBox(
                    height: (working.length * 56.0).clamp(120, 360),
                    child: ReorderableListView.builder(
                      primary: false,
                      // Mobile: Flutter does NOT paint default handles — only long-press on the
                      // row (often broken in bottom sheets). Desktop: handle is trailing. Use an
                      // explicit leading grip + ReorderableDragStartListener on all platforms.
                      buildDefaultDragHandles: false,
                      shrinkWrap: true,
                      physics: working.length > 5
                          ? const ClampingScrollPhysics()
                          : const NeverScrollableScrollPhysics(),
                      itemCount: working.length,
                      onReorder: (oldIndex, newIndex) async {
                        if (newIndex > oldIndex) newIndex -= 1;
                        setModalState(() {
                          final item = working.removeAt(oldIndex);
                          working.insert(newIndex, item);
                        });
                        final newIds = working.map((e) => e.id).toList();
                        liveOrder = liveOrder.withIdsFor(scope, newIds);
                        try {
                          await profileRepo.updateGroceryListOrder(
                            user.id,
                            liveOrder,
                          );
                          ref.invalidate(profileProvider);
                        } catch (_) {
                          if (ctx.mounted) {
                            ScaffoldMessenger.of(ctx).showSnackBar(
                              const SnackBar(
                                content: Text('Could not save list order.'),
                              ),
                            );
                          }
                        }
                      },
                      itemBuilder: (ctx, index) {
                        final list = working[index];
                        final scheme = Theme.of(ctx).colorScheme;
                        return Material(
                          key: ValueKey(list.id),
                          color: scheme.surfaceContainerLow,
                          child: ListTile(
                            leading: working.length > 1
                                ? ReorderableDragStartListener(
                                    index: index,
                                    child: SizedBox(
                                      width: 40,
                                      height: 40,
                                      child: Icon(
                                        Icons.drag_handle_rounded,
                                        color: scheme.onSurface,
                                      ),
                                    ),
                                  )
                                : SizedBox(
                                    width: 40,
                                    height: 40,
                                    child: Icon(
                                      Icons.list_rounded,
                                      color: scheme.onSurface
                                          .withValues(alpha: 0.45),
                                    ),
                                  ),
                            title: Text(list.name),
                            trailing: IconButton(
                              tooltip: 'Delete list',
                              icon: Icon(
                                Icons.delete_outline_rounded,
                                color: scheme.error,
                              ),
                              onPressed: () async {
                                final deleted = await _confirmDeleteList(
                                  list,
                                  anchorContext: ctx,
                                );
                                if (!deleted || !mounted) return;
                                setModalState(() {
                                  working.removeWhere((e) => e.id == list.id);
                                  liveOrder = liveOrder.withIdsFor(
                                    scope,
                                    working.map((e) => e.id).toList(),
                                  );
                                });
                                if (working.isEmpty && sheetCtx.mounted) {
                                  Navigator.of(sheetCtx).pop();
                                }
                              },
                            ),
                          ),
                        );
                      },
                    ),
                  ),
                ],
              ),
            );
          },
        );
      },
    );
  }

  Future<void> _openCreateListSheet(ListScope defaultScope) async {
    final user = ref.read(currentUserProvider);
    if (user == null) return;
    final nameCtrl = TextEditingController();
    var scope = defaultScope;
    final result = await showModalBottomSheet<({String id, ListScope scope})>(
      context: context,
      showDragHandle: true,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setModalState) => BrandedSheetScaffold(
          title: 'Create list',
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: nameCtrl,
                autofocus: true,
                textCapitalization: TextCapitalization.sentences,
                decoration: const InputDecoration(
                  labelText: 'List name',
                ),
              ),
              const SizedBox(height: 8),
              SegmentedButton<ListScope>(
                segments: const [
                  ButtonSegment(
                    value: ListScope.household,
                    label: Text('Household'),
                  ),
                  ButtonSegment(
                    value: ListScope.private,
                    label: Text('Private'),
                  ),
                ],
                selected: {scope},
                onSelectionChanged: (value) {
                  setModalState(() => scope = value.first);
                },
              ),
              const SizedBox(height: 8),
              SizedBox(
                width: double.infinity,
                child: FilledButton(
                  onPressed: () async {
                    if (nameCtrl.text.trim().isEmpty) return;
                    try {
                      final createdList = await ref
                          .read(groceryRepositoryProvider)
                          .createList(
                            userId: user.id,
                            name: nameCtrl.text.trim(),
                            scope: scope,
                          );
                      if (!ctx.mounted) return;
                      Navigator.of(ctx).pop(
                        (id: createdList.id, scope: scope),
                      );
                    } catch (_) {
                      if (!ctx.mounted) return;
                      Navigator.of(ctx).pop(null);
                      ScaffoldMessenger.of(ctx).showSnackBar(
                        const SnackBar(
                          content: Text('Could not create list.'),
                        ),
                      );
                    }
                  },
                  child: const Text('Create'),
                ),
              ),
            ],
          ),
        ),
      ),
    );
    if (!mounted || result == null) return;
    ref.invalidate(listsProvider);
    ref.invalidate(profileProvider);
    ref.read(selectedListIdProvider.notifier).state = result.id;
    final newScopeIdx = result.scope == ListScope.household ? 0 : 1;
    if (_listScopeIndex != newScopeIdx) {
      setState(() => _listScopeIndex = newScopeIdx);
    }
  }

  /// Returns true if the list was deleted on the server.
  Future<bool> _confirmDeleteList(
    AppList list, {
    BuildContext? anchorContext,
  }) async {
    final user = ref.read(currentUserProvider);
    if (user == null) return false;
    final householdNote = list.scope == ListScope.household
        ? ' Household members will no longer see this list.'
        : '';
    final sheetContext = anchorContext ?? context;
    final confirmed = await showModalBottomSheet<bool>(
      context: sheetContext,
      showDragHandle: true,
      builder: (context) => BrandedSheetScaffold(
        title: 'Delete list?',
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Delete "${list.name}"? All items will be removed. This cannot be undone.$householdNote',
            ),
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
                    style: FilledButton.styleFrom(
                      backgroundColor: Theme.of(context).colorScheme.error,
                      foregroundColor: Theme.of(context).colorScheme.onError,
                    ),
                    onPressed: () => Navigator.of(context).pop(true),
                    child: const Text('Delete'),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
    if (confirmed != true || !mounted) return false;
    try {
      await ref.read(groceryRepositoryProvider).deleteList(
            userId: user.id,
            list: list,
          );
      if (ref.read(selectedListIdProvider) == list.id) {
        ref.read(selectedListIdProvider.notifier).state = null;
      }
      ref.invalidate(listsProvider);
      ref.invalidate(profileProvider);
      ref.invalidate(groceryItemsProvider);
      if (!mounted) return false;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Deleted "${list.name}"')),
      );
      return true;
    } on PostgrestException catch (e) {
      if (!mounted) return false;
      final msg = e.message.toLowerCase();
      final friendly = msg.contains('row-level security') ||
              msg.contains('violates row-level') ||
              msg.contains('permission denied')
          ? 'You don\'t have permission to delete this list.'
          : 'Could not delete list. Try again.';
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(friendly)),
      );
      return false;
    } catch (_) {
      if (!mounted) return false;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Could not delete list. Try again.')),
      );
      return false;
    }
  }

  Future<void> _promptUpdateQuantity(GroceryItem item) async {
    final qtyCtrl = TextEditingController(
      text: _displayQuantity(_safeQuantity(item.quantity, fallback: 1)),
    );
    final nextQuantity = await showModalBottomSheet<String>(
      context: context,
      showDragHandle: true,
      isScrollControlled: true,
      useSafeArea: true,
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
    final listsAsync = ref.watch(listsProvider);
    final selectedListId = ref.watch(selectedListIdProvider);
    final currentUser = ref.watch(currentUserProvider);
    final hasSharedHousehold =
        ref.watch(hasSharedHouseholdProvider).valueOrNull ?? false;
    final profileAsync = ref.watch(profileProvider);

    return Scaffold(
      resizeToAvoidBottomInset: false,
      appBar: AppBar(
        title: const Text('Lists'),
        actions: [
          IconButton(
            icon: const Icon(Icons.share_outlined),
            onPressed: () async {
              final messenger = ScaffoldMessenger.of(context);
              final async = ref.read(groceryItemsProvider);
              final List<GroceryItem> items;
              if (async.hasValue) {
                items = async.requireValue;
              } else {
                final sid = ref.read(selectedListIdProvider);
                if (sid != null && sid.isNotEmpty) {
                  items = await ref.read(groceryListItemsFamily(sid).future);
                } else {
                  items =
                      await ref.read(groceryItemsDefaultListStreamProvider.future);
                }
              }
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
      body: Builder(
        builder: (context) {
          if (itemsAsync.hasError && !itemsAsync.hasValue) {
            return Center(child: Text('Error: ${itemsAsync.error}'));
          }

          final lists = listsAsync.valueOrNull ?? [];
          final selectedScope = lists
              .firstWhereOrNull((l) => l.id == selectedListId)
              ?.scope;
          final householdNewBadges = selectedScope == ListScope.household &&
              currentUser != null;
          final viewerId = currentUser?.id;
          final items = itemsAsync.valueOrNull;
          final itemsAreaLoading =
              itemsAsync.isLoading && !itemsAsync.hasValue;
          final recentsAll = ref.watch(groceryRecentsProvider);
          final filteredRecents = () {
            if (itemsAreaLoading || items == null) {
              return <RecentGroceryEntry>[];
            }
            final cart = items;
            return recentsAll
                .where(
                  (r) => !cart
                      .map((i) => normalizeGroceryItemName(i.name))
                      .contains(normalizeGroceryItemName(r.name)),
                )
                .take(24)
                .toList();
          }();

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
                        itemsAreaLoading
                            ? 'Loading items…'
                            : '${items?.length ?? 0} items',
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
              listsAsync.when(
                data: (lists) {
                  final effectiveScopeIndex =
                      hasSharedHousehold ? _listScopeIndex : 0;
                  final scopeFilter = !hasSharedHousehold
                      ? ListScope.private
                      : (effectiveScopeIndex == 0
                          ? ListScope.household
                          : ListScope.private);
                  final listOrder = profileAsync.valueOrNull?.groceryListOrder ??
                      GroceryListOrder.empty;
                  final orderedFilteredLists =
                      applyGroceryListOrder(lists, scopeFilter, listOrder);

                  if (orderedFilteredLists.isNotEmpty) {
                    final hasValid = selectedListId != null &&
                        orderedFilteredLists.any((l) => l.id == selectedListId);
                    if (!hasValid) {
                      WidgetsBinding.instance.addPostFrameCallback((_) {
                        ref.read(selectedListIdProvider.notifier).state =
                            orderedFilteredLists.first.id;
                      });
                    }
                  }

                  final dropdownValue = selectedListId != null &&
                          orderedFilteredLists.any((l) => l.id == selectedListId)
                      ? selectedListId
                      : orderedFilteredLists.firstOrNull?.id;

                  return Column(
                    children: [
                      if (hasSharedHousehold) ...[
                        SegmentedPills(
                          labels: const ['Shared', 'Private'],
                          selectedIndex: effectiveScopeIndex,
                          onSelect: (idx) {
                            setState(() => _listScopeIndex = idx);
                            final newScope = idx == 0
                                ? ListScope.household
                                : ListScope.private;
                            final order = ref
                                    .read(profileProvider)
                                    .valueOrNull
                                    ?.groceryListOrder ??
                                GroceryListOrder.empty;
                            final newScopeLists =
                                applyGroceryListOrder(lists, newScope, order);
                            final currentStillVisible = newScopeLists
                                .any((l) => l.id == selectedListId);
                            if (!currentStillVisible &&
                                newScopeLists.isNotEmpty) {
                              ref
                                  .read(selectedListIdProvider.notifier)
                                  .state = newScopeLists.first.id;
                            }
                          },
                        ),
                        const SizedBox(height: 10),
                      ],
                      Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Expanded(
                            child: orderedFilteredLists.isEmpty
                                ? Text(
                                    'No lists yet',
                                    style: Theme.of(context)
                                        .textTheme
                                        .bodyMedium,
                                  )
                                : InputDecorator(
                                    decoration: const InputDecoration(
                                      border: OutlineInputBorder(),
                                      isDense: true,
                                      contentPadding: EdgeInsets.symmetric(
                                        horizontal: 12,
                                        vertical: 4,
                                      ),
                                    ),
                                    child: DropdownButtonHideUnderline(
                                      child: DropdownButton<String>(
                                        value: dropdownValue,
                                        isExpanded: true,
                                        isDense: true,
                                        items: orderedFilteredLists
                                            .map(
                                              (list) =>
                                                  DropdownMenuItem<String>(
                                                value: list.id,
                                                child: Text(list.name),
                                              ),
                                            )
                                            .toList(),
                                        onChanged: (id) {
                                          if (id != null) {
                                            ref
                                                .read(selectedListIdProvider
                                                    .notifier)
                                                .state = id;
                                          }
                                        },
                                      ),
                                    ),
                                  ),
                          ),
                          IconButton(
                            tooltip: 'Reorder or delete lists',
                            onPressed: orderedFilteredLists.isEmpty
                                ? null
                                : () => _openReorderListSheet(
                                      orderedLists: orderedFilteredLists,
                                      scope: scopeFilter,
                                    ),
                            icon: const Icon(Icons.sort_rounded),
                          ),
                          IconButton(
                            tooltip: 'New list',
                            onPressed: () =>
                                _openCreateListSheet(scopeFilter),
                            icon: const Icon(Icons.add_circle_outline_rounded),
                          ),
                        ],
                      ),
                    ],
                  );
                },
                loading: () => const SizedBox.shrink(),
                error: (_, __) => const SizedBox.shrink(),
              ),
              const SizedBox(height: 4),
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
              else if (itemsAreaLoading || items == null)
                const SectionCard(
                  child: SizedBox(
                    height: 160,
                    child: Center(child: CircularProgressIndicator()),
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
                        gridDelegate:
                            const SliverGridDelegateWithFixedCrossAxisCount(
                          crossAxisCount: crossAxisCount,
                          mainAxisSpacing: _groceryCardGridSpacing,
                          crossAxisSpacing: _groceryCardGridSpacing,
                          childAspectRatio: _groceryCardAspectRatio,
                        ),
                        itemBuilder: (context, index) {
                          final item = items[index];
                          final showNewBadge = householdNewBadges &&
                              item.addedByUserId != null &&
                              item.addedByUserId != viewerId;
                          return _GroceryItemCard(
                            item: item,
                            showNewBadge: showNewBadge,
                            onRemove: _removeItem,
                            onUpdateQuantity: _promptUpdateQuantity,
                          );
                        },
                      );
                    },
                  ),
                ),
              if (filteredRecents.isNotEmpty) ...[
                const SizedBox(height: 16),
                Padding(
                  padding: const EdgeInsets.only(left: 4, bottom: 8),
                  child: Text(
                    'Recent items',
                    style: Theme.of(context).textTheme.titleSmall?.copyWith(
                          fontWeight: FontWeight.w700,
                        ),
                  ),
                ),
                SectionCard(
                  child: LayoutBuilder(
                    builder: (context, constraints) {
                      const crossAxisCount = 3;
                      return GridView.builder(
                        shrinkWrap: true,
                        physics: const NeverScrollableScrollPhysics(),
                        itemCount: filteredRecents.length,
                        gridDelegate:
                            const SliverGridDelegateWithFixedCrossAxisCount(
                          crossAxisCount: crossAxisCount,
                          mainAxisSpacing: _groceryCardGridSpacing,
                          crossAxisSpacing: _groceryCardGridSpacing,
                          childAspectRatio: _groceryCardAspectRatio,
                        ),
                        itemBuilder: (context, index) {
                          final entry = filteredRecents[index];
                          return _RecentGroceryEntryCard(
                            entry: entry,
                            onTap: () => _addFromRecent(entry, items ?? const []),
                          );
                        },
                      );
                    },
                  ),
                ),
              ],
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
        .map((item) => normalizeGroceryItemName(item.name))
        .where((name) => name.isNotEmpty)
        .toSet();
    final typedQuery = _nameCtrl.text.trim();
    final normalizedTypedQuery = normalizeGroceryItemName(typedQuery);
    final hasExactSuggestion = suggestions.any(
      (entry) => normalizeGroceryItemName(entry) == normalizedTypedQuery,
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
      top: true,
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
                        textCapitalization: TextCapitalization.sentences,
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
                                        final existing = widget.currentItems
                                            .firstWhereOrNull(
                                          (item) =>
                                              normalizeGroceryItemName(
                                                      item.name) ==
                                              normalizeGroceryItemName(
                                                  suggestion),
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
                  child: const Text('Add to list'),
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
    required this.showNewBadge,
    required this.onRemove,
    required this.onUpdateQuantity,
  });

  final GroceryItem item;
  final bool showNewBadge;
  final Future<void> Function(GroceryItem item) onRemove;
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
        onTap: () => onRemove(item),
        onLongPress: () => onUpdateQuantity(item),
        child: LayoutBuilder(
          builder: (context, constraints) {
            final availableHeight = constraints.maxHeight - 20;
            final ultraCompact = availableHeight < 126;
            final compact = availableHeight < 150;
            const iconSize = 38.0;
            return Stack(
              clipBehavior: Clip.none,
              children: [
                Positioned.fill(
                  child: Padding(
                    padding: EdgeInsets.symmetric(
                      horizontal: 8,
                      vertical: ultraCompact ? 5 : (compact ? 7 : 10),
                    ),
                    child: SizedBox(
                      width: double.infinity,
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        crossAxisAlignment: CrossAxisAlignment.center,
                        children: [
                        Center(
                          child: foodAsset != null
                              ? Image.asset(
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
                              : Icon(
                                  _iconForName(
                                    item.name,
                                    fallback: item.category.icon,
                                  ),
                                  color: item.category.tint,
                                  size: iconSize,
                                ),
                        ),
                        SizedBox(height: ultraCompact ? 4 : (compact ? 6 : 8)),
                        SizedBox(
                          width: double.infinity,
                          child: Text(
                            item.name,
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                            textAlign: TextAlign.center,
                            style: TextStyle(
                              color: scheme.onSurface,
                              fontWeight: FontWeight.w600,
                              fontSize: ultraCompact ? 12 : 12,
                            ),
                          ),
                        ),
                        if (ultraCompact && hasMultipleQuantity) ...[
                          const SizedBox(height: 2),
                          SizedBox(
                            width: double.infinity,
                            child: Text(
                              '(${_displayQuantity(quantityValue)})',
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              textAlign: TextAlign.center,
                              style: TextStyle(
                                color:
                                    scheme.onSurface.withValues(alpha: 0.78),
                                fontSize: 11,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ),
                        ],
                        if (hasMultipleQuantity && !ultraCompact) ...[
                          SizedBox(height: compact ? 2 : 4),
                          Align(
                            alignment: Alignment.center,
                            child: Container(
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
                  ),
                ),
                ),
                if (showNewBadge)
                  Positioned(
                    top: 4,
                    right: 4,
                    child: DecoratedBox(
                      decoration: BoxDecoration(
                        color: scheme.secondaryContainer,
                        borderRadius: BorderRadius.circular(6),
                      ),
                      child: Padding(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 6,
                          vertical: 2,
                        ),
                        child: Text(
                          'New',
                          style: TextStyle(
                            color: scheme.onSecondaryContainer,
                            fontSize: 9,
                            fontWeight: FontWeight.w700,
                            height: 1.1,
                          ),
                        ),
                      ),
                    ),
                  ),
              ],
            );
          },
        ),
      ),
    );
  }
}

class _RecentGroceryEntryCard extends StatelessWidget {
  const _RecentGroceryEntryCard({
    required this.entry,
    required this.onTap,
  });

  final RecentGroceryEntry entry;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final quantityValue = _safeQuantity(entry.quantity, fallback: 1);
    final hasMultipleQuantity = quantityValue > 1;
    final quantityLabel = entry.unit == null || entry.unit!.trim().isEmpty
        ? _displayQuantity(quantityValue)
        : '${_displayQuantity(quantityValue)} ${entry.unit!.trim()}';
    final scheme = Theme.of(context).colorScheme;
    final foodAsset =
        foodIconAssetForName(entry.name, category: entry.category);
    return Material(
      color: scheme.surfaceContainerHighest.withValues(alpha: 0.72),
      borderRadius: BorderRadius.circular(16),
      child: InkWell(
        borderRadius: BorderRadius.circular(16),
        onTap: onTap,
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
              child: SizedBox(
                width: double.infinity,
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  crossAxisAlignment: CrossAxisAlignment.center,
                  children: [
                    Center(
                      child: foodAsset != null
                          ? Image.asset(
                              foodAsset,
                              width: iconSize,
                              height: iconSize,
                              filterQuality: FilterQuality.high,
                              errorBuilder: (context, error, stackTrace) {
                                return Icon(
                                  _iconForName(
                                    entry.name,
                                    fallback: entry.category.icon,
                                  ),
                                  color: entry.category.tint,
                                  size: iconSize,
                                );
                              },
                            )
                          : Icon(
                              _iconForName(
                                entry.name,
                                fallback: entry.category.icon,
                              ),
                              color: entry.category.tint,
                              size: iconSize,
                            ),
                    ),
                    SizedBox(height: ultraCompact ? 4 : (compact ? 6 : 8)),
                    SizedBox(
                      width: double.infinity,
                      child: Text(
                        entry.name,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        textAlign: TextAlign.center,
                        style: TextStyle(
                          color: scheme.onSurface.withValues(alpha: 0.85),
                          fontWeight: FontWeight.w600,
                          fontSize: ultraCompact ? 12 : 12,
                        ),
                      ),
                    ),
                    if (ultraCompact && hasMultipleQuantity) ...[
                      const SizedBox(height: 2),
                      SizedBox(
                        width: double.infinity,
                        child: Text(
                          '(${_displayQuantity(quantityValue)})',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          textAlign: TextAlign.center,
                          style: TextStyle(
                            color: scheme.onSurface.withValues(alpha: 0.65),
                            fontSize: 11,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
                    ],
                    if (hasMultipleQuantity && !ultraCompact) ...[
                      SizedBox(height: compact ? 2 : 4),
                      Align(
                        alignment: Alignment.center,
                        child: Container(
                          padding: EdgeInsets.symmetric(
                            horizontal: compact ? 7 : 8,
                            vertical: compact ? 2 : 4,
                          ),
                          decoration: BoxDecoration(
                            color: scheme.secondaryContainer
                                .withValues(alpha: 0.85),
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
                      ),
                    ],
                  ],
                ),
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
