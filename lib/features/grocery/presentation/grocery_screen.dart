import 'dart:async';
import 'dart:math' as math;

import 'package:collection/collection.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:plateplan/core/models/app_models.dart';
import 'package:plateplan/core/theme/design_tokens.dart';
import 'package:plateplan/core/ui/discover_shell.dart';
import 'package:plateplan/core/ui/food_icon_resolver.dart';
import 'package:plateplan/core/ui/recipo_kit.dart';
import 'package:plateplan/core/ui/section_card.dart';
import 'package:plateplan/features/auth/data/auth_providers.dart';
import 'package:plateplan/features/grocery/data/grocery_repository.dart';
import 'package:plateplan/features/pantry/data/pantry_providers.dart';
import 'package:plateplan/features/grocery/presentation/grocery_item_suggestions_grid.dart';
import 'package:reorderable_grid_view/reorderable_grid_view.dart';
import 'package:plateplan/features/household/data/household_providers.dart';
import 'package:plateplan/features/profile/data/profile_providers.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

const double _groceryCardGridSpacing = kGroceryCardGridSpacing;
const double _groceryCardAspectRatio = kGroceryCardAspectRatio;

/// Custom swap / reorder control (lists ingredients card).
const String _groceryListReorderAsset = 'assets/images/grocery_list_reorder.png';

/// Lists grid cards — very light blue (light mode); subtle blue-gray (dark).
/// When [purchased] is true, the item is still on the list but marked done from
/// home — use a softer fill so it reads differently from open items.
Color _groceryListItemCardColor(BuildContext context, {bool purchased = false}) {
  final scheme = Theme.of(context).colorScheme;
  final isDark = Theme.of(context).brightness == Brightness.dark;
  final base = isDark
      ? (Color.lerp(
              scheme.surfaceContainerHighest,
              scheme.primary,
              0.12,
            ) ??
            scheme.surfaceContainerHighest)
      : const Color(0xFFEFF6FC);
  if (!purchased) return base;
  return isDark
      ? (Color.lerp(base, scheme.surfaceContainerLow, 0.5) ?? base)
      : (Color.lerp(base, scheme.surfaceContainerHighest, 0.75) ?? base);
}

class GroceryScreen extends ConsumerStatefulWidget {
  const GroceryScreen({super.key});

  @override
  ConsumerState<GroceryScreen> createState() => _GroceryScreenState();
}

class _GroceryScreenState extends ConsumerState<GroceryScreen> {
  bool _addSheetOpen = false;
  int _listScopeIndex = 0;
  final Set<String> _migratedRecentsForListIds = <String>{};

  /// Jiggle + drag reorder; persisted when user taps Save in the toolbar.
  bool _groceryReorderMode = false;
  List<GroceryItem>? _reorderWorkingItems;

  /// After a successful reorder save, stream data can lag; keep showing the
  /// saved order until [groceryListItemsFamily] emits the same id sequence.
  List<GroceryItem>? _pendingReorderDisplayItems;
  String? _pendingReorderListId;

  @override
  void initState() {
    super.initState();
    // Warm up catalog in background to avoid blocking when opening the add sheet.
    unawaited(ref.read(groceryRepositoryProvider).ensureCatalogLoaded());
  }

  Future<void> _removeItem(GroceryItem item) async {
    try {
      final listId = (item.listId ?? '').trim();
      if (listId.isNotEmpty) {
        await ref
            .read(groceryRecentsProvider(listId).notifier)
            .recordRemovedItem(item);
      }
      await ref.read(groceryRepositoryProvider).removeItem(item.id);
      invalidateActiveGroceryStreams(ref);
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Could not remove item right now.')),
      );
    }
  }

  Future<void> _toggleGroceryItemDone(GroceryItem item) async {
    final next =
        item.isDone ? GroceryItemStatus.open : GroceryItemStatus.done;
    try {
      await ref.read(groceryRepositoryProvider).updateItemStatus(item.id, next);
      if (next == GroceryItemStatus.done) {
        final hid = ref.read(activeHouseholdIdProvider);
        if (hid != null && hid.isNotEmpty) {
          await ref.read(pantryRepositoryProvider).applyPurchaseToPantryIfMatched(
                householdId: hid,
                itemName: item.name,
                quantityStr: item.quantity,
                unit: item.unit,
              );
        }
      }
      invalidateActiveGroceryStreams(ref);
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Could not update item right now.')),
      );
    }
  }

  Future<void> _onGroceryItemPrimaryTap(GroceryItem item) async {
    return _removeItem(item);
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
        quantity:
            entry.quantity?.trim().isNotEmpty == true ? entry.quantity : '1',
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
    invalidateActiveGroceryStreams(ref);
    final listId = (ref.read(selectedListIdProvider) ?? '').trim();
    if (listId.isNotEmpty) {
      ref.invalidate(groceryRecentsProvider(listId));
    }
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
    invalidateActiveGroceryStreams(ref);
    final listId = (ref.read(selectedListIdProvider) ?? '').trim();
    if (listId.isNotEmpty) {
      ref.invalidate(groceryRecentsProvider(listId));
    }
  }

  Future<void> _openCreateListSheet(ListScope defaultScope) async {
    final user = ref.read(currentUserProvider);
    if (user == null) return;
    final nameCtrl = TextEditingController();
    var scope = defaultScope;
    var kind = kListKindGeneral;
    final result = await showModalBottomSheet<
        ({String id, ListScope scope, String name})>(
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
              SegmentedButton<String>(
                segments: const [
                  ButtonSegment(
                    value: kListKindGeneral,
                    label: Text('General'),
                  ),
                  ButtonSegment(
                    value: kListKindGrocery,
                    label: Text('Grocery'),
                  ),
                ],
                selected: {kind},
                onSelectionChanged: (value) {
                  if (value.isEmpty) return;
                  setModalState(() => kind = value.first);
                },
              ),
              const SizedBox(height: 8),
              SizedBox(
                width: double.infinity,
                child: FilledButton(
                  onPressed: () async {
                    if (nameCtrl.text.trim().isEmpty) return;
                    try {
                      final createdList =
                          await ref.read(groceryRepositoryProvider).createList(
                                userId: user.id,
                                name: nameCtrl.text.trim(),
                                scope: scope,
                                kind: kind,
                              );
                      if (!ctx.mounted) return;
                      Navigator.of(ctx).pop(
                        (
                          id: createdList.id,
                          scope: scope,
                          name: createdList.name,
                        ),
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
    await ref.read(listsProvider.future);
    await ref.read(profileProvider.future);
    if (!mounted) return;
    ref.read(selectedListIdProvider.notifier).state = result.id;
    final newScopeIdx = result.scope == ListScope.household ? 0 : 1;
    if (_listScopeIndex != newScopeIdx) {
      setState(() => _listScopeIndex = newScopeIdx);
    }
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          "Created \"${result.name}\". You're now on that list.",
        ),
      ),
    );
  }

  Future<void> _promptEditList(AppList list) async {
    final user = ref.read(currentUserProvider);
    if (user == null) return;
    final ctrl = TextEditingController(text: list.name);
    var kind = (list.kind.trim().isEmpty ? kListKindGeneral : list.kind.trim());
    final result = await showModalBottomSheet<({String name, String kind})>(
      context: context,
      showDragHandle: true,
      isScrollControlled: true,
      useSafeArea: true,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setModalState) {
          final bottom = MediaQuery.of(ctx).viewInsets.bottom;
          return Padding(
            padding: EdgeInsets.fromLTRB(16, 8, 16, bottom + 16),
            child: BrandedSheetScaffold(
              title: 'Edit list',
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  TextField(
                    controller: ctrl,
                    autofocus: true,
                    textCapitalization: TextCapitalization.sentences,
                    decoration: const InputDecoration(labelText: 'List name'),
                    onSubmitted: (v) {
                      final name = v.trim();
                      if (name.isEmpty) return;
                      FocusManager.instance.primaryFocus?.unfocus();
                      WidgetsBinding.instance.addPostFrameCallback((_) {
                        if (!ctx.mounted) return;
                        Navigator.of(ctx).pop((name: name, kind: kind));
                      });
                    },
                  ),
                  const SizedBox(height: 10),
                  SegmentedButton<String>(
                    segments: const [
                      ButtonSegment(
                        value: kListKindGeneral,
                        label: Text('General'),
                      ),
                      ButtonSegment(
                        value: kListKindGrocery,
                        label: Text('Grocery'),
                      ),
                    ],
                    selected: {kind},
                    onSelectionChanged: (value) {
                      if (value.isEmpty) return;
                      setModalState(() => kind = value.first);
                    },
                  ),
                  const SizedBox(height: 10),
                  SizedBox(
                    width: double.infinity,
                    child: FilledButton(
                      onPressed: () {
                        final name = ctrl.text.trim();
                        if (name.isEmpty) return;
                        FocusManager.instance.primaryFocus?.unfocus();
                        WidgetsBinding.instance.addPostFrameCallback((_) {
                          if (!ctx.mounted) return;
                          Navigator.of(ctx).pop((name: name, kind: kind));
                        });
                      },
                      child: const Text('Save'),
                    ),
                  ),
                ],
              ),
            ),
          );
        },
      ),
    );
    ctrl.dispose();
    if (!mounted || result == null) return;
    // Let the bottom sheet route fully dispose before invalidating providers.
    await Future<void>.delayed(Duration.zero);
    final trimmed = result.name.trim();
    final nextKind = result.kind.trim();
    final sameName = trimmed == list.name;
    final sameKind = nextKind == list.kind.trim();
    if (trimmed.isEmpty || (sameName && sameKind)) return;
    try {
      await ref.read(groceryRepositoryProvider).updateList(
            listId: list.id,
            name: trimmed,
            kind: nextKind,
          );
      ref.invalidate(listsProvider);
      await ref.read(listsProvider.future);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('List updated.')),
      );
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Could not update list right now.')),
      );
    }
  }

  Future<void> _promptDeleteList(AppList list) async {
    final user = ref.read(currentUserProvider);
    if (user == null) return;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Delete list?'),
        content: Text(
          'Delete "${list.name}" and all its items? This cannot be undone.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            child: const Text('Delete'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;
    try {
      await ref
          .read(groceryRepositoryProvider)
          .deleteList(userId: user.id, list: list);
      ref.invalidate(listsProvider);
      ref.invalidate(profileProvider);
      await ref.read(listsProvider.future);
      await ref.read(profileProvider.future);
      if (!mounted) return;
      final lists = ref.read(listsProvider).valueOrNull ?? const <AppList>[];
      final selected = ref.read(selectedListIdProvider);
      if (selected == list.id) {
        final fallback = lists.firstWhereOrNull((l) => l.scope == list.scope) ??
            lists.firstOrNull;
        ref.read(selectedListIdProvider.notifier).state = fallback?.id;
      }
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('List deleted.')),
      );
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Could not delete list right now.')),
      );
    }
  }

  void _openRecentItemActions(RecentGroceryEntry entry) {
    final scheme = Theme.of(context).colorScheme;
    showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      builder: (ctx) {
        return SafeArea(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              ListTile(
                leading: Icon(Icons.delete_outline_rounded, color: scheme.error),
                title: Text(
                  'Delete from recents',
                  style: TextStyle(
                    color: scheme.error,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                onTap: () async {
                  Navigator.of(ctx).pop();
                  final listId = (ref.read(selectedListIdProvider) ?? '').trim();
                  if (listId.isEmpty) return;
                  await ref
                      .read(groceryRecentsProvider(listId).notifier)
                      .deleteRecent(entry);
                  if (!mounted) return;
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(content: Text('Deleted "${entry.name}" from recents')),
                  );
                },
              ),
            ],
          ),
        );
      },
    );
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
      invalidateActiveGroceryStreams(ref);
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

  void _openGroceryItemActions(GroceryItem item) {
    final scheme = Theme.of(context).colorScheme;
    showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      builder: (ctx) {
        return SafeArea(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              ListTile(
                leading: const Icon(Icons.edit_outlined),
                title: const Text('Change quantity'),
                onTap: () {
                  Navigator.of(ctx).pop();
                  unawaited(_promptUpdateQuantity(item));
                },
              ),
              ListTile(
                leading: Icon(
                  Icons.delete_outline_rounded,
                  color: scheme.error,
                ),
                title: Text(
                  'Remove from list',
                  style: TextStyle(
                    color: scheme.error,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                onTap: () {
                  Navigator.of(ctx).pop();
                  unawaited(_removeItem(item));
                },
              ),
            ],
          ),
        );
      },
    );
  }

  void _onGroceryWorkingReorder(int oldIndex, int newIndex) {
    setState(() {
      final list = List<GroceryItem>.from(_reorderWorkingItems!);
      final moved = list.removeAt(oldIndex);
      list.insert(newIndex, moved);
      _reorderWorkingItems = list;
    });
  }

  Future<void> _saveGroceryReorderFromWorking(String listId) async {
    final working = _reorderWorkingItems;
    if (working == null) return;
    try {
      await ref.read(groceryRepositoryProvider).reorderListItems(
            listId: listId,
            orderedItemIds: working.map((e) => e.id).toList(),
          );
      if (mounted) {
        // Phase 1: commit pending overlay while still in reorder mode so the grid
        // keeps using [_reorderWorkingItems] (correct order) for this frame.
        setState(() {
          _pendingReorderDisplayItems = List<GroceryItem>.from(working);
          _pendingReorderListId = listId;
        });
        // Phase 2: exit reorder on the next frame so merge logic can clear pending
        // only when !_groceryReorderMode (avoids premature clear — see
        // [mergeGroceryDisplayWithPendingReorder]).
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (!mounted) return;
          setState(() {
            _groceryReorderMode = false;
            _reorderWorkingItems = null;
          });
        });
        // Do not call [invalidateActiveGroceryStreams] here: reorder_list_items
        // issues UPDATEs; the existing Realtime subscription already refetches via
        // pushFresh. Invalidating recreates the stream and races the pending
        // overlay (one frame of stale list order).
      }
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Could not save item order right now.')),
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

    return DiscoverShellScaffold(
      title: 'Lists',
      onNotificationsTap: () => showDiscoverNotificationsDropdown(context, ref),
      resizeToAvoidBottomInset: false,
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
          final selectedScope =
              lists.firstWhereOrNull((l) => l.id == selectedListId)?.scope;
          final householdNewBadges =
              selectedScope == ListScope.household && currentUser != null;
          final viewerId = currentUser?.id;
          final items = itemsAsync.valueOrNull;
          final sortMode = ref.watch(groceryItemsSortModeProvider);
          /// Same list id [groceryItemsProvider] uses for the item stream.
          final String? itemsStreamListId = effectiveGroceryListId(
            lists: lists,
            selectedListId: selectedListId,
            hasSharedHousehold: hasSharedHousehold,
            profileOrder: listOrder,
          );

          // One-time migration: legacy builds stored recents globally (not per list).
          // If the active list has no per-list recents yet, copy the legacy set into it.
          final activeListIdForRecents = (itemsStreamListId ?? '').trim();
          if (activeListIdForRecents.isNotEmpty &&
              !_migratedRecentsForListIds.contains(activeListIdForRecents)) {
            _migratedRecentsForListIds.add(activeListIdForRecents);
            WidgetsBinding.instance.addPostFrameCallback((_) async {
              if (!mounted) return;
              final repo = ref.read(groceryRepositoryProvider);
              final wrote = await repo.migrateGlobalRecentsToListIfEmpty(
                listId: activeListIdForRecents,
              );
              if (!mounted || !wrote) return;
              ref.invalidate(groceryRecentsProvider(activeListIdForRecents));
            });
          }
          final activeItemsList = itemsStreamListId == null
              ? null
              : lists.firstWhereOrNull((l) => l.id == itemsStreamListId);
          final isGroceryKindActive = activeItemsList?.kind == kListKindGrocery;

          if (isGroceryKindActive &&
              sortMode != GroceryItemsSortMode.byCategory &&
              !_groceryReorderMode) {
            WidgetsBinding.instance.addPostFrameCallback((_) {
              if (!mounted) return;
              ref.read(groceryItemsSortModeProvider.notifier).state =
                  GroceryItemsSortMode.byCategory;
            });
          }

          List<GroceryItem>? displayItems;
          if (items == null) {
            displayItems = null;
          } else {
            displayItems = applyGroceryItemsSort(items, sortMode);
            final pending = _pendingReorderDisplayItems;
            final pendingListId = _pendingReorderListId;
            final merge = mergeGroceryDisplayWithPendingReorder(
              streamItems: items,
              sortMode: sortMode,
              pending: pending,
              pendingListId: pendingListId,
              reorderEditModeActive: _groceryReorderMode,
            );
            if (merge != null) {
              displayItems = merge.displayItems;
              if (merge.scheduleClearPending) {
                WidgetsBinding.instance.addPostFrameCallback((_) {
                  if (!mounted) return;
                  setState(() {
                    _pendingReorderDisplayItems = null;
                    _pendingReorderListId = null;
                  });
                });
              }
            }
          }
          final itemsAreaLoading = itemsAsync.isLoading && !itemsAsync.hasValue;
          final recentsAll = (itemsStreamListId != null &&
                  itemsStreamListId.isNotEmpty)
              ? ref.watch(groceryRecentsProvider(itemsStreamListId))
              : const <RecentGroceryEntry>[];
          final filteredRecents = () {
            if (itemsAreaLoading || items == null) {
              return <RecentGroceryEntry>[];
            }
            final cart = items;
            final list = recentsAll
                .where(
                  (r) => !cart
                      .map((i) => normalizeGroceryItemName(i.name))
                      .contains(normalizeGroceryItemName(r.name)),
                )
                .take(24)
                .toList();
            list.sort(
              (a, b) =>
                  a.name.toLowerCase().compareTo(b.name.toLowerCase()),
            );
            return list;
          }();

          return ListView(
            padding: const EdgeInsets.fromLTRB(12, 10, 12, 96),
            children: [
              listsAsync.when(
                data: (_) {
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

                  final activeListId = selectedListId != null &&
                          orderedFilteredLists
                              .any((l) => l.id == selectedListId)
                      ? selectedListId
                      : orderedFilteredLists.firstOrNull?.id;
                  final activeList = activeListId == null
                      ? null
                      : lists.firstWhereOrNull((l) => l.id == activeListId);

                  return _ListsToolbar(
                    hasSharedHousehold: hasSharedHousehold,
                    effectiveScopeIndex: effectiveScopeIndex,
                    onScopeSelected: (idx) {
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
                      final currentStillVisible =
                          newScopeLists.any((l) => l.id == selectedListId);
                      if (!currentStillVisible && newScopeLists.isNotEmpty) {
                        ref.read(selectedListIdProvider.notifier).state =
                            newScopeLists.first.id;
                      }
                    },
                    orderedFilteredLists: orderedFilteredLists,
                    activeListId: activeListId,
                    isGroceryKindActive: activeList?.kind == kListKindGrocery,
                    activeList: activeList,
                    onListSelected: (id) {
                      final clearPending = _pendingReorderDisplayItems != null;
                      if (_groceryReorderMode || clearPending) {
                        setState(() {
                          if (_groceryReorderMode) {
                            _groceryReorderMode = false;
                            _reorderWorkingItems = null;
                          }
                          _pendingReorderDisplayItems = null;
                          _pendingReorderListId = null;
                        });
                      }
                      ref.read(selectedListIdProvider.notifier).state = id;
                    },
                    itemsAreaLoading: itemsAreaLoading,
                    itemCount: items?.length ?? 0,
                    sortMode: sortMode,
                    onSortModeSelected: (mode) {
                      final clearPending = _pendingReorderDisplayItems != null;
                      if (_groceryReorderMode || clearPending) {
                        setState(() {
                          if (_groceryReorderMode) {
                            _groceryReorderMode = false;
                            _reorderWorkingItems = null;
                          }
                          _pendingReorderDisplayItems = null;
                          _pendingReorderListId = null;
                        });
                      }
                      ref.read(groceryItemsSortModeProvider.notifier).state =
                          mode;
                    },
                    onNewList: () => _openCreateListSheet(scopeFilter),
                    onRenameList: (list) => unawaited(_promptEditList(list)),
                    onDeleteList: (list) => unawaited(_promptDeleteList(list)),
                  );
                },
                loading: () => const SizedBox.shrink(),
                error: (_, __) => const SizedBox.shrink(),
              ),
              const SizedBox(height: 12),
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
                            'Adding item… Long-press an item in the list to edit quantity.',
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
                  child: Builder(
                    builder: (context) {
                      final scheme = Theme.of(context).colorScheme;
                      final repo = ref.read(groceryRepositoryProvider);
                      final showReorderIcon = !isGroceryKindActive &&
                          items.length > 1 &&
                          sortMode == GroceryItemsSortMode.asAdded &&
                          itemsStreamListId != null &&
                          itemsStreamListId.isNotEmpty &&
                          orderedFilteredLists.isNotEmpty;

                      Widget sectionedGrocery() {
                        // Existing DB rows may have stale/unknown category values (e.g. older
                        // installs or newly added keywords). For Grocery lists, re-categorize
                        // "Other" locally for display so the UI improves immediately without a
                        // migration/backfill.
                        final list = (displayItems ?? const <GroceryItem>[])
                            .map((i) {
                              if (i.category != GroceryCategory.other) return i;
                              final next = repo.categorize(i.name);
                              if (next == GroceryCategory.other) return i;
                              return i.copyWith(category: next);
                            })
                            .toList();
                        const crossAxisCount = 3;
                        final categories = GroceryCategory.values;
                        final theme = Theme.of(context);
                        final headerStyle =
                            theme.textTheme.titleSmall?.copyWith(
                          fontWeight: FontWeight.w800,
                        );

                        List<GroceryItem> itemsFor(GroceryCategory c) =>
                            list.where((i) => i.category == c).toList();

                        Widget gridFor(List<GroceryItem> sectionItems) {
                          Widget cardFor(GroceryItem item) {
                            final showNewBadge = householdNewBadges &&
                                item.addedByUserId != null &&
                                item.addedByUserId != viewerId;
                            return _GroceryItemCard(
                              key: ValueKey(item.id),
                              item: item,
                              showNewBadge: showNewBadge,
                              reorderEditMode: false,
                              reorderJiggle: false,
                              onPrimaryTap: _onGroceryItemPrimaryTap,
                              onLongPressMenu: () =>
                                  _openGroceryItemActions(item),
                            );
                          }

                          return GridView.count(
                            shrinkWrap: true,
                            physics: const NeverScrollableScrollPhysics(),
                            crossAxisCount: crossAxisCount,
                            crossAxisSpacing: _groceryCardGridSpacing,
                            mainAxisSpacing: _groceryCardGridSpacing,
                            childAspectRatio: _groceryCardAspectRatio,
                            children: sectionItems.map(cardFor).toList(),
                          );
                        }

                        final children = <Widget>[];
                        for (final c in categories) {
                          final sectionItems = itemsFor(c);
                          if (sectionItems.isEmpty) continue;
                          children.addAll([
                            Padding(
                              padding:
                                  const EdgeInsets.fromLTRB(6, 8, 6, 8),
                              child: Text(c.label, style: headerStyle),
                            ),
                            Padding(
                              padding:
                                  const EdgeInsets.symmetric(horizontal: 2),
                              child: gridFor(sectionItems),
                            ),
                            const SizedBox(height: 12),
                          ]);
                        }
                        if (children.isEmpty) {
                          return const SizedBox.shrink();
                        }
                        // Remove trailing space.
                        if (children.last is SizedBox) {
                          children.removeLast();
                        }
                        return Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: children,
                        );
                      }

                      void onReorderIconPressed() {
                        final id = itemsStreamListId;
                        if (id == null ||
                            id.isEmpty ||
                            displayItems == null ||
                            displayItems.isEmpty) {
                          return;
                        }
                        if (_groceryReorderMode) {
                          unawaited(_saveGroceryReorderFromWorking(id));
                        } else {
                          final toCopy = displayItems;
                          setState(() {
                            _groceryReorderMode = true;
                            _reorderWorkingItems =
                                List<GroceryItem>.from(toCopy);
                            _pendingReorderDisplayItems = null;
                            _pendingReorderListId = null;
                          });
                        }
                      }

                      return Stack(
                        clipBehavior: Clip.none,
                        children: [
                          if (isGroceryKindActive)
                            Padding(
                              padding: const EdgeInsets.only(top: 4),
                              child: sectionedGrocery(),
                            )
                          else
                            Padding(
                              padding: EdgeInsets.only(
                                top: showReorderIcon ? 36 : 0,
                              ),
                              child: LayoutBuilder(
                                builder: (context, constraints) {
                                  const crossAxisCount = 3;
                                  final list = _groceryReorderMode &&
                                          _reorderWorkingItems != null
                                      ? _reorderWorkingItems!
                                      : displayItems!;
                                  final useReorderGrid = _groceryReorderMode &&
                                      _reorderWorkingItems != null &&
                                      list.length > 1 &&
                                      itemsStreamListId != null &&
                                      itemsStreamListId.isNotEmpty;
                                  Widget cardFor(GroceryItem item) {
                                    final showNewBadge = householdNewBadges &&
                                        item.addedByUserId != null &&
                                        item.addedByUserId != viewerId;
                                    return _GroceryItemCard(
                                      key: ValueKey(item.id),
                                      item: item,
                                      showNewBadge: showNewBadge,
                                      reorderEditMode: _groceryReorderMode,
                                      reorderJiggle: _groceryReorderMode,
                                      onPrimaryTap: _onGroceryItemPrimaryTap,
                                      onLongPressMenu: () =>
                                          _openGroceryItemActions(item),
                                    );
                                  }

                                  // Always use [ReorderableGridView] so Save does not swap to
                                  // [GridView.builder] (different element types caused a one-frame
                                  // flash of the pre-drag layout when the reorder grid disposed).
                                  return ReorderableGridView.count(
                                    key: ValueKey<bool>(_groceryReorderMode),
                                    shrinkWrap: true,
                                    physics:
                                        const NeverScrollableScrollPhysics(),
                                    crossAxisCount: crossAxisCount,
                                    crossAxisSpacing: _groceryCardGridSpacing,
                                    mainAxisSpacing: _groceryCardGridSpacing,
                                    childAspectRatio: _groceryCardAspectRatio,
                                    dragEnabled: useReorderGrid,
                                    dragStartDelay: useReorderGrid
                                        ? Duration.zero
                                        : const Duration(milliseconds: 1),
                                    onReorder: (oldIndex, newIndex) {
                                      if (!useReorderGrid) return;
                                      _onGroceryWorkingReorder(
                                          oldIndex, newIndex);
                                    },
                                    children: list.map(cardFor).toList(),
                                  );
                                },
                              ),
                            ),
                          if (showReorderIcon)
                            Positioned(
                              top: 0,
                              right: 0,
                              child: Row(
                                mainAxisSize: MainAxisSize.min,
                                crossAxisAlignment: CrossAxisAlignment.center,
                                children: [
                                  Padding(
                                    padding: const EdgeInsets.only(right: 2),
                                    child: Text(
                                      _groceryReorderMode
                                          ? 'Save order'
                                          : 'Reorder',
                                      style: Theme.of(context)
                                          .textTheme
                                          .labelLarge
                                          ?.copyWith(
                                            fontWeight: FontWeight.w700,
                                            color: _groceryReorderMode
                                                ? scheme.primary
                                                : scheme.onSurfaceVariant,
                                          ),
                                    ),
                                  ),
                                  IconButton(
                                    tooltip: _groceryReorderMode
                                        ? 'Save item order'
                                        : 'Reorder items in this list',
                                    style: IconButton.styleFrom(
                                      padding: EdgeInsets.zero,
                                      minimumSize: const Size(40, 40),
                                      tapTargetSize:
                                          MaterialTapTargetSize.shrinkWrap,
                                      foregroundColor: _groceryReorderMode
                                          ? scheme.primary
                                          : scheme.onSurfaceVariant,
                                    ),
                                    onPressed: onReorderIconPressed,
                                    icon: _groceryReorderMode
                                        ? const Icon(
                                            Icons.check_rounded,
                                            size: 26,
                                          )
                                        : Image.asset(
                                            _groceryListReorderAsset,
                                            width: 26,
                                            height: 26,
                                            fit: BoxFit.contain,
                                            color: scheme.onSurfaceVariant,
                                            colorBlendMode: BlendMode.srcIn,
                                          ),
                                  ),
                                ],
                              ),
                            ),
                        ],
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
                            onTap: () =>
                                _addFromRecent(entry, items ?? const []),
                            onLongPress: () => _openRecentItemActions(entry),
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

  @override
  void initState() {
    super.initState();
    _nameCtrl = TextEditingController();
    _qtyCtrl = TextEditingController(text: '1');
    _searchFocusNode = FocusNode(debugLabel: 'grocery_search');
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

  @override
  void dispose() {
    _searchDebounce?.cancel();
    _searchFocusNode.dispose();
    _nameCtrl.dispose();
    _qtyCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
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
                        textInputAction: TextInputAction.done,
                        onChanged: (_) => setState(() {}),
                        onSubmitted: (value) {
                          final name = value.trim();
                          if (name.isEmpty) return;
                          FocusManager.instance.primaryFocus?.unfocus();
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
                      GroceryItemSuggestionsGrid(
                        repo: widget.repo,
                        typedValue: _nameCtrl.text,
                        recentItems: widget.currentItems,
                        duplicateMessage:
                            'Already in basket. Long-press the item in your list to edit quantity.',
                        onPick: (suggestion) {
                          FocusManager.instance.primaryFocus?.unfocus();
                          final quantity = _displayQuantity(
                            _safeQuantity(_qtyCtrl.text, fallback: 1),
                          );
                          Navigator.of(context).pop(
                            _PendingGroceryItem(
                              name: suggestion,
                              quantity: quantity,
                            ),
                          );
                        },
                      ),
                      const SizedBox(height: 12),
                    ],
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

class _ListsToolbar extends StatelessWidget {
  const _ListsToolbar({
    required this.hasSharedHousehold,
    required this.effectiveScopeIndex,
    required this.onScopeSelected,
    required this.orderedFilteredLists,
    required this.activeListId,
    required this.isGroceryKindActive,
    required this.activeList,
    required this.onListSelected,
    required this.itemsAreaLoading,
    required this.itemCount,
    required this.sortMode,
    required this.onSortModeSelected,
    required this.onNewList,
    required this.onRenameList,
    required this.onDeleteList,
  });

  final bool hasSharedHousehold;
  final int effectiveScopeIndex;
  final ValueChanged<int> onScopeSelected;
  final List<AppList> orderedFilteredLists;
  final String? activeListId;
  final bool isGroceryKindActive;
  final AppList? activeList;
  final ValueChanged<String> onListSelected;
  final bool itemsAreaLoading;
  final int itemCount;
  final GroceryItemsSortMode sortMode;
  final ValueChanged<GroceryItemsSortMode> onSortModeSelected;
  final VoidCallback onNewList;
  final ValueChanged<AppList> onRenameList;
  final ValueChanged<AppList> onDeleteList;

  void _openListPicker(BuildContext context) {
    if (orderedFilteredLists.isEmpty) {
      return;
    }
    final scheme = Theme.of(context).colorScheme;
    showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      builder: (ctx) {
        final maxH = MediaQuery.sizeOf(ctx).height * 0.55;
        return SafeArea(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 4, 20, 8),
                child: Text(
                  'Choose list',
                  style: Theme.of(ctx).textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.w700,
                      ),
                ),
              ),
              ConstrainedBox(
                constraints: BoxConstraints(maxHeight: maxH),
                child: ListView.builder(
                  shrinkWrap: true,
                  itemCount: orderedFilteredLists.length,
                  itemBuilder: (context, index) {
                    final list = orderedFilteredLists[index];
                    final selected = list.id == activeListId;
                    return ListTile(
                      title: Text(list.name),
                      trailing: selected
                          ? Icon(Icons.check_rounded, color: scheme.primary)
                          : null,
                      onTap: () {
                        Navigator.of(ctx).pop();
                        onListSelected(list.id);
                      },
                    );
                  },
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;
    final displayName = orderedFilteredLists.isEmpty
        ? ''
        : (orderedFilteredLists.firstWhereOrNull((l) => l.id == activeListId) ??
                orderedFilteredLists.first)
            .name;

    return Material(
      color: scheme.surfaceContainerLow,
      elevation: 0,
      shadowColor: Colors.transparent,
      shape: RoundedRectangleBorder(
        borderRadius: AppRadius.md,
        side: BorderSide(
          color: scheme.outlineVariant.withValues(alpha: 0.45),
        ),
      ),
      clipBehavior: Clip.antiAlias,
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            if (hasSharedHousehold) ...[
              SizedBox(
                width: double.infinity,
                child: SegmentedButton<int>(
                  segments: const [
                    ButtonSegment<int>(
                      value: 0,
                      label: Text('Shared'),
                    ),
                    ButtonSegment<int>(
                      value: 1,
                      label: Text('Private'),
                    ),
                  ],
                  selected: {effectiveScopeIndex},
                  onSelectionChanged: (next) {
                    if (next.isEmpty) {
                      return;
                    }
                    onScopeSelected(next.first);
                  },
                ),
              ),
              const SizedBox(height: 12),
            ],
            Row(
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      if (orderedFilteredLists.isEmpty)
                        Text(
                          'No lists yet',
                          style: textTheme.titleSmall?.copyWith(
                            fontWeight: FontWeight.w700,
                          ),
                        )
                      else
                        InkWell(
                          onTap: () => _openListPicker(context),
                          borderRadius: BorderRadius.circular(8),
                          child: Padding(
                            padding: const EdgeInsets.symmetric(
                              vertical: 4,
                              horizontal: 2,
                            ),
                            child: Text(
                              displayName,
                              style: textTheme.titleSmall?.copyWith(
                                fontWeight: FontWeight.w800,
                              ),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                        ),
                      const SizedBox(height: 4),
                      Text(
                        itemsAreaLoading
                            ? 'Loading items…'
                            : '$itemCount ${itemCount == 1 ? 'item' : 'items'}',
                        style: textTheme.bodySmall?.copyWith(
                          color: scheme.onSurfaceVariant,
                        ),
                      ),
                    ],
                  ),
                ),
                Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    if (orderedFilteredLists.isNotEmpty)
                      IconButton(
                        tooltip: 'Choose list',
                        style: IconButton.styleFrom(
                          padding: const EdgeInsets.fromLTRB(8, 8, 0, 8),
                          minimumSize: Size.zero,
                          tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                        ),
                        onPressed: () => _openListPicker(context),
                        icon: Icon(
                          Icons.keyboard_arrow_down_rounded,
                          color: scheme.onSurfaceVariant,
                        ),
                      ),
                    PopupMenuButton<String>(
                      tooltip: 'List actions',
                      padding: orderedFilteredLists.isNotEmpty
                          ? const EdgeInsets.fromLTRB(0, 8, 4, 8)
                          : EdgeInsets.zero,
                      icon: Icon(
                        Icons.more_vert_rounded,
                        color: scheme.onSurfaceVariant,
                      ),
                      onSelected: (value) {
                        switch (value) {
                          case 'new':
                            onNewList();
                          case 'rename':
                            final l = activeList;
                            if (l != null) onRenameList(l);
                          case 'delete':
                            final l = activeList;
                            if (l != null) onDeleteList(l);
                          case 'sort_as_added':
                            onSortModeSelected(GroceryItemsSortMode.asAdded);
                          case 'sort_alpha':
                            onSortModeSelected(
                              GroceryItemsSortMode.alphabetical,
                            );
                        }
                      },
                      itemBuilder: (context) => [
                        PopupMenuItem<String>(
                          value: 'rename',
                          enabled: activeList != null,
                          child: const Text('Edit list'),
                        ),
                        PopupMenuItem<String>(
                          value: 'delete',
                          enabled: activeList != null,
                          child: Text(
                            'Delete list',
                            style: TextStyle(color: scheme.error),
                          ),
                        ),
                        const PopupMenuDivider(),
                        if (!isGroceryKindActive) ...[
                          PopupMenuItem<String>(
                            value: 'sort_as_added',
                            enabled: orderedFilteredLists.isNotEmpty,
                            child: Row(
                              children: [
                                SizedBox(
                                  width: 28,
                                  child:
                                      sortMode == GroceryItemsSortMode.asAdded
                                          ? Icon(Icons.check_rounded,
                                              size: 20, color: scheme.primary)
                                          : null,
                                ),
                                Expanded(
                                  child: Text(
                                    GroceryItemsSortMode.asAdded.menuLabel,
                                  ),
                                ),
                              ],
                            ),
                          ),
                          PopupMenuItem<String>(
                            value: 'sort_alpha',
                            enabled: orderedFilteredLists.isNotEmpty,
                            child: Row(
                              children: [
                                SizedBox(
                                  width: 28,
                                  child: sortMode ==
                                          GroceryItemsSortMode.alphabetical
                                      ? Icon(Icons.check_rounded,
                                          size: 20, color: scheme.primary)
                                      : null,
                                ),
                                Expanded(
                                  child: Text(
                                    GroceryItemsSortMode.alphabetical.menuLabel,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ],
                        const PopupMenuItem<String>(
                          value: 'new',
                          child: Text('New list'),
                        ),
                      ],
                    ),
                  ],
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _GroceryReorderJiggle extends StatefulWidget {
  const _GroceryReorderJiggle({
    required this.active,
    required this.child,
  });

  final bool active;
  final Widget child;

  @override
  State<_GroceryReorderJiggle> createState() => _GroceryReorderJiggleState();
}

class _GroceryReorderJiggleState extends State<_GroceryReorderJiggle>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 160),
    );
    if (widget.active) {
      _controller.repeat(reverse: true);
    }
  }

  @override
  void didUpdateWidget(_GroceryReorderJiggle oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.active && !oldWidget.active) {
      _controller.repeat(reverse: true);
    } else if (!widget.active && oldWidget.active) {
      _controller
        ..stop()
        ..reset();
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (!widget.active) return widget.child;
    return AnimatedBuilder(
      animation: _controller,
      child: widget.child,
      builder: (context, child) {
        final t = _controller.value * math.pi * 2;
        // iOS-style jiggle: visible tilt + slight horizontal wobble (phase-shifted).
        final angle = 0.0325 * math.sin(t);
        final dx = 0.55 * math.sin(t + 1.1);
        return Transform.translate(
          offset: Offset(dx, 0),
          child: Transform.rotate(
            angle: angle,
            child: child,
          ),
        );
      },
    );
  }
}

class _GroceryItemCard extends StatelessWidget {
  const _GroceryItemCard({
    super.key,
    required this.item,
    required this.showNewBadge,
    this.reorderEditMode = false,
    this.reorderJiggle = false,
    required this.onPrimaryTap,
    required this.onLongPressMenu,
  });

  final GroceryItem item;
  final bool showNewBadge;
  final bool reorderEditMode;
  final bool reorderJiggle;
  final Future<void> Function(GroceryItem item) onPrimaryTap;
  final VoidCallback onLongPressMenu;

  @override
  Widget build(BuildContext context) {
    final quantityValue = _safeQuantity(item.quantity, fallback: 1);
    final hasMultipleQuantity = quantityValue > 1;
    final quantityLabel = item.unit == null || item.unit!.trim().isEmpty
        ? _displayQuantity(quantityValue)
        : '${_displayQuantity(quantityValue)} ${item.unit!.trim()}';
    final scheme = Theme.of(context).colorScheme;
    final foodAsset = foodIconAssetForName(item.name, category: item.category);
    final nameStyle = TextStyle(
      color: scheme.onSurface.withValues(alpha: item.isDone ? 0.55 : 1),
      fontWeight: FontWeight.w600,
      fontSize: 12,
      decoration: item.isDone ? TextDecoration.lineThrough : null,
      decorationColor: scheme.onSurface.withValues(alpha: 0.45),
    );
    return _GroceryReorderJiggle(
      active: reorderJiggle,
      child: Material(
        color: _groceryListItemCardColor(context, purchased: item.isDone),
        borderRadius: BorderRadius.circular(16),
        clipBehavior: Clip.none,
        child: Stack(
          clipBehavior: Clip.none,
          children: [
            InkWell(
              borderRadius: BorderRadius.circular(16),
              onTap: reorderEditMode ? null : () => unawaited(onPrimaryTap(item)),
              onLongPress: reorderEditMode ? null : onLongPressMenu,
              child: LayoutBuilder(
                builder: (context, constraints) {
                  final availableHeight = constraints.maxHeight - 20;
                  final ultraCompact = availableHeight < 126;
                  final compact = availableHeight < 150;
                  const iconSize = 38.0;
                  final showsExtraFooterRow =
                      (hasMultipleQuantity) || (item.fromPlanner && !compact);
                  final iconChild = foodAsset != null
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
                        );
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
                          Center(child: iconChild),
                          SizedBox(
                            height: ultraCompact ? 4 : (compact ? 6 : 8),
                          ),
                          SizedBox(
                            width: double.infinity,
                            child: Text(
                              item.name,
                              // Prevent overflow when the card also shows quantity / planner badge.
                              // Those add vertical rows; keep the name compact in that case.
                              maxLines: showsExtraFooterRow ? 1 : 2,
                              overflow: TextOverflow.ellipsis,
                              textAlign: TextAlign.center,
                              style: nameStyle,
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
                );
              },
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
      ),
    ),
    );
  }
}

class _RecentGroceryEntryCard extends StatelessWidget {
  const _RecentGroceryEntryCard({
    required this.entry,
    required this.onTap,
    required this.onLongPress,
  });

  final RecentGroceryEntry entry;
  final VoidCallback onTap;
  final VoidCallback onLongPress;

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
        onLongPress: onLongPress,
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
  if (lower.contains('milk') || lower.contains('cream')) {
    return Icons.local_drink_rounded;
  }
  if (lower.contains('cheese')) return Icons.breakfast_dining_rounded;
  if (lower.contains('granola') || lower.contains('cereal')) {
    return Icons.breakfast_dining_rounded;
  }
  if (lower.contains('banana')) return Icons.energy_savings_leaf_rounded;
  if (lower.contains('blueberr') ||
      lower.contains('strawberr') ||
      lower.contains('blackberr') ||
      lower.contains('raspberr')) {
    return Icons.local_florist_rounded;
  }
  if (lower.contains('grape')) return Icons.local_florist_rounded;
  if (lower.contains('bread') || lower.contains('bagel')) {
    return Icons.bakery_dining_rounded;
  }
  if (lower.contains('jam')) return Icons.breakfast_dining_rounded;
  if (lower.contains('juice')) return Icons.local_bar_rounded;
  if (lower.contains('potato')) return Icons.circle_rounded;
  if (lower.contains('carrot')) return Icons.grass_rounded;
  if (lower.contains('apple')) return Icons.apple_rounded;
  if (lower.contains('orange')) return Icons.local_florist_rounded;
  if (lower.contains('mushroom')) return Icons.grass_rounded;
  if (lower.contains('broccoli')) return Icons.spa_rounded;
  if (lower.contains('bacon') || lower.contains('sausage')) {
    return Icons.set_meal_rounded;
  }
  if (lower.contains('shrimp')) return Icons.set_meal_rounded;
  if (lower.contains('tortilla') || lower.contains('salsa')) {
    return Icons.restaurant_rounded;
  }
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
