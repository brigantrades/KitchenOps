import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:plateplan/core/models/app_models.dart';
import 'package:plateplan/core/pantry/pantry_quantity_math.dart';
import 'package:plateplan/core/ui/discover_shell.dart';
import 'package:plateplan/core/ui/section_card.dart';
import 'package:plateplan/features/auth/data/auth_providers.dart';
import 'package:plateplan/features/grocery/data/grocery_repository.dart';
import 'package:plateplan/features/grocery/presentation/grocery_item_suggestions_grid.dart';
import 'package:plateplan/features/household/data/household_providers.dart';
import 'package:plateplan/features/pantry/data/pantry_providers.dart';
import 'package:plateplan/features/pantry/domain/pantry_deficit.dart';

class PantryScreen extends ConsumerStatefulWidget {
  const PantryScreen({super.key});

  @override
  ConsumerState<PantryScreen> createState() => _PantryScreenState();
}

class _PantryScreenState extends ConsumerState<PantryScreen> {
  final Set<String> _selectedDeficitKeys = {};

  @override
  Widget build(BuildContext context) {
    final householdId = ref.watch(activeHouseholdIdProvider);
    final itemsAsync = ref.watch(pantryItemsProvider);
    final deficitsAsync = ref.watch(pantryDeficitsForPlannerProvider);

    return DiscoverShellScaffold(
      title: 'Pantry',
      onNotificationsTap: () => showDiscoverNotificationsDropdown(context, ref),
      body: householdId == null || householdId.isEmpty
          ? const _NoHouseholdBody()
          : SingleChildScrollView(
              padding: const EdgeInsets.fromLTRB(0, 2, 0, 24),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Padding(
                    padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
                    child: Row(
                      children: [
                        Expanded(
                          child: Text(
                            'Inventory for your household. Compare to the meal plan to fill the shopping list.',
                            style: Theme.of(context).textTheme.bodyMedium,
                          ),
                        ),
                        TextButton.icon(
                          onPressed: () async {
                            final repo = ref.read(pantryRepositoryProvider);
                            try {
                              await repo.markAllAuditedNow(householdId);
                              if (!context.mounted) return;
                              ScaffoldMessenger.of(context).showSnackBar(
                                const SnackBar(
                                  content: Text('Marked all items audited.'),
                                ),
                              );
                            } catch (_) {
                              if (!context.mounted) return;
                              ScaffoldMessenger.of(context).showSnackBar(
                                const SnackBar(
                                  content: Text('Could not update audit time.'),
                                ),
                              );
                            }
                          },
                          icon: const Icon(Icons.fact_check_outlined, size: 18),
                          label: const Text('Audit done'),
                        ),
                      ],
                    ),
                  ),
                  deficitsAsync.when(
                    loading: () => const Padding(
                      padding: EdgeInsets.all(24),
                      child: Center(child: CircularProgressIndicator()),
                    ),
                    error: (e, _) => Padding(
                      padding: const EdgeInsets.all(16),
                      child: Text('Could not compute shortages: $e'),
                    ),
                    data: (result) => _DeficitsSection(
                      result: result,
                      selectedKeys: _selectedDeficitKeys,
                      onToggle: (key) {
                        setState(() {
                          if (_selectedDeficitKeys.contains(key)) {
                            _selectedDeficitKeys.remove(key);
                          } else {
                            _selectedDeficitKeys.add(key);
                          }
                        });
                      },
                      onAddSelected: () => unawaited(
                        _addSelectedDeficitsToGrocery(context, ref, result),
                      ),
                    ),
                  ),
                  const SizedBox(height: 8),
                  itemsAsync.when(
                    loading: () => const Padding(
                      padding: EdgeInsets.all(24),
                      child: Center(child: CircularProgressIndicator()),
                    ),
                    error: (e, _) => Padding(
                      padding: const EdgeInsets.all(16),
                      child: Text('Could not load pantry: $e'),
                    ),
                    data: (items) => items.isEmpty
                        ? Padding(
                            padding: const EdgeInsets.all(24),
                            child: Text(
                              'No pantry items yet. Tap + to add staples.',
                              style: Theme.of(context).textTheme.bodyMedium,
                              textAlign: TextAlign.center,
                            ),
                          )
                        : SectionCard(
                            title: 'Stock',
                            padding: const EdgeInsets.fromLTRB(12, 12, 12, 10),
                            child: _PantryStockTable(
                              items: items,
                              onEdit: (p) => unawaited(
                                _editPantryItem(context, ref, p),
                              ),
                              onDelete: (p) => unawaited(
                                _deletePantryItem(context, ref, p),
                              ),
                            ),
                          ),
                  ),
                ],
              ),
            ),
      floatingActionButton: householdId == null || householdId.isEmpty
          ? null
          : FloatingActionButton.extended(
              onPressed: () => unawaited(_addPantryItem(context, ref)),
              icon: const Icon(Icons.add_rounded),
              label: const Text('Add item'),
            ),
    );
  }

  Future<void> _addSelectedDeficitsToGrocery(
    BuildContext context,
    WidgetRef ref,
    PantryDeficitResult result,
  ) async {
    if (_selectedDeficitKeys.isEmpty) return;
    final user = ref.read(currentUserProvider);
    if (user == null) return;
    final grocery = ref.read(groceryRepositoryProvider);
    final listId = ref.read(selectedListIdProvider);
    final selected = result.deficits
        .where((d) => _selectedDeficitKeys.contains(_deficitKey(d)))
        .toList();
    if (selected.isEmpty) return;
    try {
      for (final d in selected) {
        final full = formatNormalizedForDisplay(d.shortfall);
        final parts = full.split(' ');
        final qtyLabel = parts.first;
        final unitRest =
            parts.length > 1 ? parts.sublist(1).join(' ') : '';
        await grocery.addItem(
          userId: user.id,
          listId: listId,
          name: d.ingredientDisplayName,
          quantity: qtyLabel,
          unit: unitRest.isEmpty ? null : unitRest,
          category: GroceryCategory.other,
        );
      }
      if (!context.mounted) return;
      setState(() => _selectedDeficitKeys.clear());
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            'Added ${selected.length} item${selected.length == 1 ? '' : 's'} to your list.',
          ),
        ),
      );
    } catch (_) {
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Could not add items to the list.')),
      );
    }
  }

  Future<void> _addPantryItem(BuildContext context, WidgetRef ref) async {
    final hid = ref.read(activeHouseholdIdProvider);
    final user = ref.read(currentUserProvider);
    if (hid == null || user == null) return;
    final existing = ref.read(pantryItemsProvider).valueOrNull ?? const [];
    final draft = await showModalBottomSheet<_PantryDraft>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      showDragHandle: true,
      builder: (ctx) => _AddPantryItemSheet(
        groceryRepo: ref.read(groceryRepositoryProvider),
        existingPantryItems: existing,
      ),
    );
    if (!context.mounted || draft == null) return;
    final name = draft.name.trim();
    if (name.isEmpty) return;
    final qty = draft.quantity;
    final unit = draft.unit.trim().isEmpty ? 'g' : draft.unit.trim();
    try {
      await ref.read(pantryRepositoryProvider).insertItem(
            householdId: hid,
            userId: user.id,
            name: name,
            currentQuantity: qty,
            unit: unit,
          );
    } catch (_) {
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Could not save pantry item.')),
      );
    }
  }

  Future<void> _editPantryItem(
    BuildContext context,
    WidgetRef ref,
    PantryItem item,
  ) async {
    final qtyCtrl =
        TextEditingController(text: item.currentQuantity.toString());
    final unitCtrl = TextEditingController(text: item.unit);
    final bufCtrl = TextEditingController(
      text: item.bufferThreshold?.toString() ?? '',
    );
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(item.name),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: qtyCtrl,
              decoration: const InputDecoration(labelText: 'Quantity'),
              keyboardType: TextInputType.number,
            ),
            TextField(
              controller: unitCtrl,
              decoration: const InputDecoration(labelText: 'Unit'),
            ),
            TextField(
              controller: bufCtrl,
              decoration: const InputDecoration(
                labelText: 'Buffer threshold (optional)',
              ),
              keyboardType: TextInputType.number,
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Save'),
          ),
        ],
      ),
    );
    if (ok != true || !context.mounted) return;
    final qty = double.tryParse(qtyCtrl.text.replaceAll(',', '.')) ?? 0;
    final unit = unitCtrl.text.trim().isEmpty ? 'g' : unitCtrl.text.trim();
    final buf = bufCtrl.text.trim().isEmpty
        ? null
        : double.tryParse(bufCtrl.text.replaceAll(',', '.'));
    try {
      await ref.read(pantryRepositoryProvider).updateItem(
            id: item.id,
            currentQuantity: qty,
            unit: unit,
            bufferThreshold: buf,
            lastAuditAt: DateTime.now(),
          );
    } catch (_) {
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Could not update item.')),
      );
    }
  }

  Future<void> _deletePantryItem(
    BuildContext context,
    WidgetRef ref,
    PantryItem item,
  ) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Remove from pantry?'),
        content: Text(item.name),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Remove'),
          ),
        ],
      ),
    );
    if (ok != true || !context.mounted) return;
    try {
      await ref.read(pantryRepositoryProvider).deleteItem(item.id);
    } catch (_) {
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Could not remove item.')),
      );
    }
  }
}

class _PantryDraft {
  const _PantryDraft({
    required this.name,
    required this.quantity,
    required this.unit,
  });

  final String name;
  final double quantity;
  final String unit;
}

class _AddPantryItemSheet extends StatefulWidget {
  const _AddPantryItemSheet({
    required this.groceryRepo,
    required this.existingPantryItems,
  });

  final GroceryRepository groceryRepo;
  final List<PantryItem> existingPantryItems;

  @override
  State<_AddPantryItemSheet> createState() => _AddPantryItemSheetState();
}

class _AddPantryItemSheetState extends State<_AddPantryItemSheet> {
  late final TextEditingController _nameCtrl;
  late final TextEditingController _qtyCtrl;
  late final TextEditingController _unitCtrl;
  late final FocusNode _nameFocus;
  String? _pickedSuggestion;
  bool _showSuggestions = true;

  @override
  void initState() {
    super.initState();
    _nameCtrl = TextEditingController();
    _qtyCtrl = TextEditingController(text: '0');
    _unitCtrl = TextEditingController(text: 'g');
    _nameFocus = FocusNode(debugLabel: 'pantry_name');
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      _nameFocus.requestFocus();
    });
    unawaited(widget.groceryRepo.ensureCatalogLoaded());
  }

  @override
  void dispose() {
    _nameCtrl.dispose();
    _qtyCtrl.dispose();
    _unitCtrl.dispose();
    _nameFocus.dispose();
    super.dispose();
  }

  List<GroceryItem> get _existingAsGroceryItems {
    return widget.existingPantryItems
        .map(
          (p) => GroceryItem(
            id: 'pantry-${p.id}',
            name: p.name,
            category: p.category,
            quantity: p.currentQuantity.toString(),
            unit: p.unit,
            fromRecipeId: null,
            listId: null,
            sourceSlotId: null,
            addedByUserId: null,
            status: GroceryItemStatus.open,
          ),
        )
        .toList();
  }

  double _parseQty(String raw, {double fallback = 0}) {
    final t = raw.trim();
    if (t.isEmpty) return fallback;
    final n = double.tryParse(t.replaceAll(',', '.'));
    return n ?? fallback;
  }

  void _pickSuggestion(String name) {
    setState(() {
      _nameCtrl.text = name;
      _pickedSuggestion = name;
      _showSuggestions = false;
    });
    _nameFocus.unfocus();
  }

  void _submit() {
    final name = _nameCtrl.text.trim();
    if (name.isEmpty) return;
    final qty = _parseQty(_qtyCtrl.text, fallback: 0);
    final unit = _unitCtrl.text.trim();
    Navigator.of(context).pop(
      _PantryDraft(name: name, quantity: qty, unit: unit),
    );
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final typed = _nameCtrl.text.trim();
    final picked = _pickedSuggestion?.trim();
    return DraggableScrollableSheet(
      initialChildSize: 0.86,
      minChildSize: 0.55,
      maxChildSize: 0.96,
      expand: false,
      builder: (context, scrollCtrl) {
        return Material(
          color: scheme.surface,
          child: ListView(
            controller: scrollCtrl,
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
            children: [
              Text(
                'Add pantry item',
                style: Theme.of(context)
                    .textTheme
                    .titleLarge
                    ?.copyWith(fontWeight: FontWeight.w800),
              ),
              const SizedBox(height: 10),
              TextField(
                controller: _nameCtrl,
                focusNode: _nameFocus,
                decoration: InputDecoration(
                  labelText: 'Item',
                  hintText: 'Start typing (e.g. pasta, milk, rice)…',
                  suffixIcon: (picked != null &&
                          picked.isNotEmpty &&
                          normalizeGroceryItemName(picked) ==
                              normalizeGroceryItemName(typed))
                      ? Icon(Icons.check_circle_rounded,
                          color: scheme.primary)
                      : null,
                ),
                textCapitalization: TextCapitalization.sentences,
                onChanged: (_) {
                  final t = _nameCtrl.text.trim();
                  final p = _pickedSuggestion?.trim();
                  final stillPicked = p != null &&
                      p.isNotEmpty &&
                      normalizeGroceryItemName(p) ==
                          normalizeGroceryItemName(t);
                  setState(() {
                    if (!stillPicked) {
                      _pickedSuggestion = null;
                      _showSuggestions = true;
                    }
                  });
                },
                onSubmitted: (_) => _submit(),
              ),
              const SizedBox(height: 10),
              if (picked != null &&
                  picked.isNotEmpty &&
                  !_showSuggestions &&
                  normalizeGroceryItemName(picked) ==
                      normalizeGroceryItemName(typed))
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                  decoration: BoxDecoration(
                    color: scheme.primaryContainer.withValues(alpha: 0.55),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Row(
                    children: [
                      Icon(Icons.check_rounded, color: scheme.primary),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Text(
                          'Selected: $picked',
                          style: Theme.of(context)
                              .textTheme
                              .bodyMedium
                              ?.copyWith(fontWeight: FontWeight.w700),
                        ),
                      ),
                      TextButton(
                        onPressed: () {
                          setState(() {
                            _pickedSuggestion = null;
                            _showSuggestions = true;
                          });
                          _nameFocus.requestFocus();
                        },
                        child: const Text('Change'),
                      ),
                    ],
                  ),
                )
              else
                GroceryItemSuggestionsGrid(
                  repo: widget.groceryRepo,
                  typedValue: _nameCtrl.text,
                  recentItems: _existingAsGroceryItems,
                  onPick: _pickSuggestion,
                  duplicateMessage:
                      'Already in pantry. Edit it in the list below.',
                  maxHeight: 280,
                ),
              const SizedBox(height: 12),
              Row(
                children: [
                  Expanded(
                    child: TextField(
                      controller: _qtyCtrl,
                      decoration: const InputDecoration(
                        labelText: 'Quantity',
                      ),
                      keyboardType: const TextInputType.numberWithOptions(
                        decimal: true,
                        signed: false,
                      ),
                      onSubmitted: (_) => _submit(),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: TextField(
                      controller: _unitCtrl,
                      decoration: const InputDecoration(
                        labelText: 'Unit',
                        hintText: 'g, ml, each',
                      ),
                      onSubmitted: (_) => _submit(),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 16),
              SizedBox(
                width: double.infinity,
                child: FilledButton.icon(
                  onPressed: _nameCtrl.text.trim().isEmpty ? null : _submit,
                  icon: const Icon(Icons.add_rounded),
                  label: const Text('Add to pantry'),
                ),
              ),
              const SizedBox(height: 8),
              Text(
                'Tip: long-press pantry rows to edit quantities later.',
                style: Theme.of(context)
                    .textTheme
                    .bodySmall
                    ?.copyWith(color: scheme.onSurfaceVariant),
              ),
            ],
          ),
        );
      },
    );
  }
}

String _deficitKey(PantryDeficit d) =>
    '${d.nameKey}|${d.kind.name}|${d.pantryItemId ?? ""}';

class _DeficitsSection extends StatelessWidget {
  const _DeficitsSection({
    required this.result,
    required this.selectedKeys,
    required this.onToggle,
    required this.onAddSelected,
  });

  final PantryDeficitResult result;
  final Set<String> selectedKeys;
  final void Function(String key) onToggle;
  final VoidCallback onAddSelected;

  @override
  Widget build(BuildContext context) {
    if (result.deficits.isEmpty && result.unmatchedNeeds.isEmpty) {
      return Padding(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
        child: Text(
          'No shortages vs your meal plan for the current planner window, or add pantry lines with matching names and units.',
          style: Theme.of(context).textTheme.bodySmall,
        ),
      );
    }
    return SectionCard(
      title: 'Suggested from meal plan',
      subtitle: 'Shortfall vs pantry (normalized units)',
      padding: const EdgeInsets.fromLTRB(8, 12, 8, 8),
      titleTrailing: result.deficits.isEmpty
          ? null
          : TextButton(
              onPressed: selectedKeys.isEmpty ? null : onAddSelected,
              child: const Text('Add selected to list'),
            ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          for (final d in result.deficits)
            CheckboxListTile(
              value: selectedKeys.contains(_deficitKey(d)),
              onChanged: (_) => onToggle(_deficitKey(d)),
              title: Text(d.ingredientDisplayName),
              subtitle: Text(
                'Need ${formatNormalizedForDisplay(d.needed)} · have ${formatNormalizedForDisplay(d.onHand!)} · short ${formatNormalizedForDisplay(d.shortfall)}',
              ),
            ),
          if (result.unmatchedNeeds.isNotEmpty) ...[
            const SizedBox(height: 8),
            Text(
              'Review manually',
              style: Theme.of(context).textTheme.titleSmall,
            ),
            for (final u in result.unmatchedNeeds)
              ListTile(
                dense: true,
                title: Text(u.ingredientDisplayName),
                subtitle: Text(
                  '${formatNormalizedForDisplay(u.normalized)} · ${u.reason ?? ""}',
                ),
              ),
          ],
        ],
      ),
    );
  }
}

// ignore: unused_element
class _PantryRow extends StatelessWidget {
  const _PantryRow({
    required this.item,
    required this.onEdit,
    required this.onDelete,
  });

  final PantryItem item;
  final VoidCallback onEdit;
  final VoidCallback onDelete;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final stock = normalizePantryAmount(
      item.currentQuantity,
      item.unit,
      qualitative: false,
    );
    final label = stock == null
        ? '${item.currentQuantity} ${item.unit}'
        : formatNormalizedForDisplay(stock);
    return ListTile(
      title: Text(item.name),
      subtitle: Text(
        [
          label,
          if (item.bufferThreshold != null)
            'buffer ${item.bufferThreshold}',
          if (item.lastAuditAt != null)
            'audited ${item.lastAuditAt!.toLocal().toString().split(' ').first}',
        ].where((s) => s.toString().isNotEmpty).join(' · '),
      ),
      trailing: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          IconButton(
            tooltip: 'Edit',
            icon: Icon(Icons.edit_outlined, color: scheme.primary),
            onPressed: onEdit,
          ),
          IconButton(
            tooltip: 'Remove',
            icon: Icon(Icons.delete_outline_rounded, color: scheme.error),
            onPressed: onDelete,
          ),
        ],
      ),
    );
  }
}

class _PantryStockTable extends StatelessWidget {
  const _PantryStockTable({
    required this.items,
    required this.onEdit,
    required this.onDelete,
  });

  final List<PantryItem> items;
  final ValueChanged<PantryItem> onEdit;
  final ValueChanged<PantryItem> onDelete;

  String _formatQty(PantryItem item) {
    final stock = normalizePantryAmount(
      item.currentQuantity,
      item.unit,
      qualitative: false,
    );
    if (stock == null) {
      final v = item.currentQuantity;
      if (v == v.roundToDouble()) return v.round().toString();
      return v.toStringAsFixed(1);
    }
    final v = stock.value;
    if (stock.kind == PantryPhysicalKind.count) {
      if (v == v.roundToDouble()) return v.round().toString();
      return v.toStringAsFixed(1);
    }
    // Canonical base values can be big; keep readable but stable.
    if (v == v.roundToDouble()) return v.round().toString();
    return v.toStringAsFixed(1);
  }

  String _formatUnit(PantryItem item) {
    final stock = normalizePantryAmount(
      item.currentQuantity,
      item.unit,
      qualitative: false,
    );
    if (stock == null) return item.unit.trim().isEmpty ? '—' : item.unit.trim();
    return stock.displayUnit;
  }

  String _formatAudit(PantryItem item) {
    final dt = item.lastAuditAt;
    if (dt == null) return '—';
    return dt.toLocal().toString().split(' ').first;
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final headerStyle = Theme.of(context).textTheme.labelLarge?.copyWith(
          fontWeight: FontWeight.w800,
          color: scheme.onSurfaceVariant,
        );
    final cellStyle = Theme.of(context).textTheme.bodyMedium?.copyWith(
          fontWeight: FontWeight.w600,
        );

    return ClipRRect(
      borderRadius: BorderRadius.circular(14),
      child: Container(
        decoration: BoxDecoration(
          border: Border.all(color: scheme.outlineVariant.withValues(alpha: 0.6)),
          borderRadius: BorderRadius.circular(14),
        ),
        child: Column(
          children: [
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
              color: scheme.surfaceContainerHighest.withValues(alpha: 0.55),
              child: Row(
                children: [
                  Expanded(flex: 5, child: Text('Item', style: headerStyle)),
                  Expanded(
                    flex: 2,
                    child: Align(
                      alignment: Alignment.centerRight,
                      child: Text('Qty', style: headerStyle),
                    ),
                  ),
                  Expanded(
                    flex: 2,
                    child: Padding(
                      padding: const EdgeInsets.only(left: 10),
                      child: Text('Unit', style: headerStyle),
                    ),
                  ),
                  Expanded(
                    flex: 3,
                    child: Padding(
                      padding: const EdgeInsets.only(left: 10),
                      child: Text('Audit', style: headerStyle),
                    ),
                  ),
                  const SizedBox(width: 36),
                ],
              ),
            ),
            for (var i = 0; i < items.length; i++)
              _PantryStockTableRow(
                item: items[i],
                zebra: i.isOdd,
                qty: _formatQty(items[i]),
                unit: _formatUnit(items[i]),
                audit: _formatAudit(items[i]),
                cellStyle: cellStyle,
                onEdit: () => onEdit(items[i]),
                onDelete: () => onDelete(items[i]),
              ),
          ],
        ),
      ),
    );
  }
}

class _PantryStockTableRow extends StatelessWidget {
  const _PantryStockTableRow({
    required this.item,
    required this.zebra,
    required this.qty,
    required this.unit,
    required this.audit,
    required this.cellStyle,
    required this.onEdit,
    required this.onDelete,
  });

  final PantryItem item;
  final bool zebra;
  final String qty;
  final String unit;
  final String audit;
  final TextStyle? cellStyle;
  final VoidCallback onEdit;
  final VoidCallback onDelete;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final bg = zebra
        ? scheme.surfaceContainerHighest.withValues(alpha: 0.18)
        : scheme.surface;

    return Container(
      color: bg,
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      child: Row(
        children: [
          Expanded(
            flex: 5,
            child: Text(
              item.name,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: cellStyle,
            ),
          ),
          Expanded(
            flex: 2,
            child: Align(
              alignment: Alignment.centerRight,
              child: Text(qty, style: cellStyle),
            ),
          ),
          Expanded(
            flex: 2,
            child: Padding(
              padding: const EdgeInsets.only(left: 10),
              child: Text(unit, style: cellStyle),
            ),
          ),
          Expanded(
            flex: 3,
            child: Padding(
              padding: const EdgeInsets.only(left: 10),
              child: Text(
                audit,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      color: scheme.onSurfaceVariant,
                      fontWeight: FontWeight.w600,
                    ),
              ),
            ),
          ),
          SizedBox(
            width: 36,
            child: PopupMenuButton<String>(
              tooltip: 'Actions',
              onSelected: (value) {
                switch (value) {
                  case 'edit':
                    onEdit();
                    break;
                  case 'delete':
                    onDelete();
                    break;
                }
              },
              itemBuilder: (context) => [
                const PopupMenuItem(
                  value: 'edit',
                  child: ListTile(
                    leading: Icon(Icons.edit_outlined),
                    title: Text('Edit'),
                  ),
                ),
                PopupMenuItem(
                  value: 'delete',
                  child: ListTile(
                    leading: Icon(
                      Icons.delete_outline_rounded,
                      color: scheme.error,
                    ),
                    title: Text(
                      'Remove',
                      style: TextStyle(
                        color: scheme.error,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                ),
              ],
              child: Icon(
                Icons.more_vert_rounded,
                color: scheme.onSurfaceVariant,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _NoHouseholdBody extends StatelessWidget {
  const _NoHouseholdBody();

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(24),
      child: Column(
        children: [
          Text(
            'Pantry is shared per household. Create or join a household in Profile to track inventory.',
            style: Theme.of(context).textTheme.bodyLarge,
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 16),
          FilledButton(
            onPressed: () => context.push('/household'),
            child: const Text('Household settings'),
          ),
        ],
      ),
    );
  }
}
