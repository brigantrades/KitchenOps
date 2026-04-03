import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:plateplan/core/models/app_models.dart';
import 'package:plateplan/core/planner_week_mapping.dart';
import 'package:plateplan/core/storage/local_cache.dart';
import 'package:plateplan/features/auth/data/auth_providers.dart';
import 'package:plateplan/features/planner/data/planner_repository.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

/// Keeps a local row order during reorder so [ReorderableListView] does not snap
/// back while persistence runs. Clears when provider data matches the new order.
class PlannerOptimisticDayReorderList extends ConsumerStatefulWidget {
  const PlannerOptimisticDayReorderList({
    super.key,
    required this.syncKey,
    required this.providerDaySlots,
    required this.itemBuilder,
    this.shrinkWrap = true,
  });

  /// Changes when week or selected day changes; resets optimistic state.
  final String syncKey;

  /// Slots for this day from [plannerSlotsProvider], sorted by [MealPlanSlot.slotOrder].
  final List<MealPlanSlot> providerDaySlots;

  final Widget Function(
    BuildContext context,
    int index,
    MealPlanSlot slot,
    List<MealPlanSlot> displaySlots,
  ) itemBuilder;

  /// When true (default), the list sizes to its children and is meant for a parent
  /// [ScrollView]. When false, use inside [Expanded] so the list scrolls and fills
  /// the remaining height.
  final bool shrinkWrap;

  @override
  ConsumerState<PlannerOptimisticDayReorderList> createState() =>
      _PlannerOptimisticDayReorderListState();
}

class _PlannerOptimisticDayReorderListState
    extends ConsumerState<PlannerOptimisticDayReorderList> {
  List<MealPlanSlot>? _optimistic;

  List<MealPlanSlot> get _displaySlots =>
      _optimistic ?? widget.providerDaySlots;

  @override
  void didUpdateWidget(covariant PlannerOptimisticDayReorderList oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.syncKey != widget.syncKey) {
      _optimistic = null;
      return;
    }
    if (_optimistic == null) return;

    final p = widget.providerDaySlots;
    if (p.length != _optimistic!.length) {
      _optimistic = null;
      return;
    }
    final sorted = [...p]..sort((a, b) => a.slotOrder.compareTo(b.slotOrder));
    var matches = true;
    for (var i = 0; i < sorted.length; i++) {
      if (sorted[i].id != _optimistic![i].id || sorted[i].slotOrder != i) {
        matches = false;
        break;
      }
    }
    if (matches) {
      _optimistic = null;
    }
  }

  Future<void> _onReorder(int oldIndex, int newIndex) async {
    if (newIndex > oldIndex) newIndex -= 1;
    final list = [..._displaySlots];
    final moved = list.removeAt(oldIndex);
    list.insert(newIndex, moved);
    final optimistic = <MealPlanSlot>[
      for (var i = 0; i < list.length; i++) list[i].copyWith(slotOrder: i),
    ];
    setState(() => _optimistic = optimistic);

    final repo = ref.read(plannerRepositoryProvider);
    try {
      await repo.reorderSlots(optimistic);
      if (!mounted) return;
      final day = plannerDateOnly(calendarDateForSlot(optimistic.first));
      final user = ref.read(currentUserProvider);
      if (user != null) {
        final anchor = ref.read(weekStartProvider);
        final pref = ref.read(effectivePlannerWindowProvider);
        await clearPlannerHiveCachesForSlotMutation(
          cache: ref.read(localCacheProvider),
          userId: user.id,
          anchor: anchor,
          pref: pref,
          calendarDate: day,
        );
      }
      invalidatePlannerSlotCaches(ref, day);
    } on PostgrestException catch (error) {
      if (!mounted) return;
      setState(() => _optimistic = null);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Could not reorder slots: ${error.message}')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final slots = _displaySlots;
    return ReorderableListView.builder(
      key: ValueKey('planner-day-${widget.syncKey}'),
      shrinkWrap: widget.shrinkWrap,
      physics: widget.shrinkWrap
          ? const NeverScrollableScrollPhysics()
          : const AlwaysScrollableScrollPhysics(),
      buildDefaultDragHandles: false,
      itemCount: slots.length,
      onReorder: _onReorder,
      itemBuilder: (context, i) {
        return widget.itemBuilder(context, i, slots[i], slots);
      },
    );
  }
}
