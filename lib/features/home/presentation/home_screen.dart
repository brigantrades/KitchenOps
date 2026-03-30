import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:collection/collection.dart';
import 'package:plateplan/core/ui/discover_shell.dart';
import 'package:plateplan/core/ui/section_card.dart';
import 'package:plateplan/core/theme/design_tokens.dart';
import 'package:plateplan/features/auth/data/auth_providers.dart';
import 'package:plateplan/features/household/data/household_providers.dart';
import 'package:plateplan/features/home/presentation/home_outlook_day_card.dart';
import 'package:plateplan/features/home/presentation/home_outlook_day_sheet.dart';
import 'package:plateplan/features/profile/data/profile_providers.dart';
import 'package:plateplan/features/recipes/data/recipes_repository.dart';
import 'package:plateplan/features/grocery/data/grocery_repository.dart';
import 'package:plateplan/features/planner/data/planner_repository.dart';
import 'package:plateplan/features/planner/presentation/planner_screen.dart';
import 'package:plateplan/core/models/app_models.dart';
import 'package:plateplan/core/planner_slot_labels.dart';
import 'package:plateplan/core/planner_week_mapping.dart';
import 'package:plateplan/core/theme/app_brand.dart';

class HomeScreen extends ConsumerWidget {
  const HomeScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return DiscoverShellScaffold(
      title: 'Home',
      onNotificationsTap: () => showDiscoverNotificationsDropdown(context, ref),
      body: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(0, 2, 0, 24),
        child: DecoratedBox(
          decoration: BoxDecoration(
            color: AppBrand.offWhite,
            borderRadius: AppRadius.md,
            border: Border.all(
              color: AppBrand.mutedAqua.withValues(alpha: 0.65),
            ),
          ),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(4, 4, 4, 8),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                const _HomeHeader(),
                const SizedBox(height: 14),
                const _HomeThreeDayOutlook(),
                const SizedBox(height: 14),
                const _HomeGrocerySnippet(),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _HomeThreeDayOutlook extends ConsumerWidget {
  const _HomeThreeDayOutlook();

  static const double _loadingMinHeight = 96;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final outlook = ref.watch(plannerThreeDayOutlookSlotsProvider);
    final recipesAsync = ref.watch(recipesProvider);
    final dates = plannerOutlookDates(DateTime.now());
    return SectionCard(
      title: '3-Day Outlook',
      subtitle: 'Next up in your meal flow',
      padding: const EdgeInsets.fromLTRB(14, 14, 14, 14),
      titleTrailing: FilledButton(
        onPressed: () => context.go('/planner'),
        style: FilledButton.styleFrom(
          visualDensity: VisualDensity.compact,
          backgroundColor: AppBrand.deepTeal,
          foregroundColor: AppBrand.offWhite,
          textStyle: Theme.of(context).textTheme.labelMedium?.copyWith(
                fontWeight: FontWeight.w700,
                color: AppBrand.offWhite,
              ),
          shape: const StadiumBorder(),
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        ),
        child: const Text('View planner'),
      ),
      child: outlook.when(
        skipLoadingOnReload: true,
        loading: () => const SizedBox(
          height: _loadingMinHeight,
          child: Center(child: CircularProgressIndicator()),
        ),
        error: (e, _) => Text(
          'Could not load outlook: $e',
          style: Theme.of(context).textTheme.bodySmall,
        ),
        data: (slots) {
          return recipesAsync.when(
            skipLoadingOnReload: true,
            loading: () => const SizedBox(
              height: _loadingMinHeight,
              child: Center(child: CircularProgressIndicator()),
            ),
            error: (e, _) => Text(
              'Could not load recipes: $e',
              style: Theme.of(context).textTheme.bodySmall,
            ),
            data: (recipes) {
              final members =
                  ref.watch(householdMembersProvider).valueOrNull ?? const [];
              final activeMembers = members
                  .where((m) => m.status == HouseholdMemberStatus.active)
                  .toList();
              final showMemberAssignment =
                  ref.watch(hasSharedHouseholdProvider).valueOrNull ?? false;
              return Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  for (var i = 0; i < dates.length; i++) ...[
                    if (i > 0) const SizedBox(height: 12),
                    HomeOutlookDayCard(
                      date: dates[i],
                      outlookIndex: i,
                      daySlots: dedupeMealPlanSlotsByIdPreferPlanned(
                        slots
                            .where((s) =>
                                plannerDateOnly(calendarDateForSlot(s)) ==
                                plannerDateOnly(dates[i]))
                            .sorted(
                                (a, b) => a.slotOrder.compareTo(b.slotOrder))
                            .toList(),
                      ),
                      recipes: recipes,
                      onTap: () {
                        final daySlots = dedupeMealPlanSlotsByIdPreferPlanned(
                          slots
                              .where((s) =>
                                  plannerDateOnly(calendarDateForSlot(s)) ==
                                  plannerDateOnly(dates[i]))
                              .sorted(
                                  (a, b) =>
                                      a.slotOrder.compareTo(b.slotOrder))
                              .toList(),
                        );
                        showHomeOutlookDayDetailSheet(
                          context: context,
                          ref: ref,
                          date: dates[i],
                          daySlots: daySlots,
                          recipes: recipes,
                        );
                      },
                      onPlanEmptySlot: (slot) {
                        final user = ref.read(currentUserProvider);
                        if (user == null) return;
                        final daySlots = dedupeMealPlanSlotsByIdPreferPlanned(
                          slots
                              .where((s) =>
                                  plannerDateOnly(calendarDateForSlot(s)) ==
                                  plannerDateOnly(dates[i]))
                              .sorted(
                                  (a, b) =>
                                      a.slotOrder.compareTo(b.slotOrder))
                              .toList(),
                        );
                        unawaited(
                          openSlotMealPlanEditorFromHome(
                            context,
                            ref,
                            slot: slot,
                            daySlots: daySlots,
                            recipes: recipes,
                            activeMembers: activeMembers,
                            currentUserId: user.id,
                            showMemberAssignment: showMemberAssignment,
                          ),
                        );
                      },
                    ),
                  ],
                ],
              );
            },
          );
        },
      ),
    );
  }
}

Future<void> _toggleGroceryItemStatus(WidgetRef ref, GroceryItem item) async {
  final next =
      item.isDone ? GroceryItemStatus.open : GroceryItemStatus.done;
  try {
    await ref.read(groceryRepositoryProvider).updateItemStatus(item.id, next);
    invalidateActiveGroceryStreams(ref);
  } catch (_) {
    // Realtime / next fetch reconciles; avoid noisy toasts for transient failures.
  }
}

Future<void> _promptClearPurchasedFromHome(
  BuildContext context,
  WidgetRef ref,
) async {
  final items = ref.read(groceryItemsProvider).valueOrNull;
  final purchasedCount = items?.where((i) => i.isDone).length ?? 0;
  if (purchasedCount == 0) return;
  final confirmed = await showDialog<bool>(
    context: context,
    builder: (ctx) => AlertDialog(
      title: const Text('Clear purchased items?'),
      content: Text(
        'Remove $purchasedCount purchased '
        '${purchasedCount == 1 ? 'item' : 'items'} from your list? '
        'This cannot be undone.',
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(ctx).pop(false),
          child: const Text('Cancel'),
        ),
        FilledButton(
          onPressed: () => Navigator.of(ctx).pop(true),
          child: const Text('Clear'),
        ),
      ],
    ),
  );
  if (confirmed != true || !context.mounted) return;
  final lists = ref.read(listsProvider).valueOrNull ?? [];
  final selectedListId = ref.read(selectedListIdProvider);
  final hasSharedHousehold =
      ref.read(hasSharedHouseholdProvider).valueOrNull ?? false;
  final profileOrder =
      ref.read(profileProvider).valueOrNull?.groceryListOrder ??
          GroceryListOrder.empty;
  final effectiveId = effectiveGroceryListId(
    lists: lists,
    selectedListId: selectedListId,
    hasSharedHousehold: hasSharedHousehold,
    profileOrder: profileOrder,
  );
  if (effectiveId == null || effectiveId.isEmpty) return;
  try {
    await ref
        .read(groceryRepositoryProvider)
        .removeDoneItemsForList(effectiveId);
    invalidateActiveGroceryStreams(ref);
    if (!context.mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          'Removed $purchasedCount purchased '
          '${purchasedCount == 1 ? 'item' : 'items'}.',
        ),
      ),
    );
  } catch (_) {
    if (!context.mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Could not clear purchased items.')),
    );
  }
}

/// Warm cream card in light mode; surface container in dark mode.
class _HomeGrocerySnippet extends ConsumerWidget {
  const _HomeGrocerySnippet();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final scheme = Theme.of(context).colorScheme;
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final async = ref.watch(groceryItemsProvider);

    return Container(
      decoration: BoxDecoration(
        color: isDark ? scheme.surfaceContainerHigh : AppBrand.offWhite,
        borderRadius: AppRadius.md,
        boxShadow: AppShadows.soft,
        border: Border.all(
          color: isDark
              ? scheme.outlineVariant.withValues(alpha: 0.35)
              : AppBrand.mutedAqua.withValues(alpha: 0.85),
        ),
      ),
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Container(
                  width: 34,
                  height: 34,
                  decoration: BoxDecoration(
                    color: isDark
                        ? scheme.surfaceContainerHighest
                        : AppBrand.paleMint,
                    shape: BoxShape.circle,
                  ),
                  child: Icon(
                    Icons.shopping_basket_rounded,
                    size: 18,
                    color: isDark ? scheme.onSurface : AppBrand.deepTeal,
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    'Grocery Snippet',
                    style: Theme.of(context).textTheme.titleMedium?.copyWith(
                          fontWeight: FontWeight.w700,
                        ),
                  ),
                ),
                TextButton.icon(
                  onPressed: () => context.go('/grocery'),
                  style: TextButton.styleFrom(
                    visualDensity: VisualDensity.compact,
                    foregroundColor:
                        isDark ? scheme.primary : AppBrand.deepTeal,
                    textStyle: Theme.of(context).textTheme.labelMedium?.copyWith(
                          fontWeight: FontWeight.w700,
                        ),
                  ),
                  icon: const Icon(Icons.arrow_forward_rounded, size: 18),
                  label: const Text('Open list'),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
              decoration: BoxDecoration(
                color: isDark
                    ? scheme.surfaceContainerHighest.withValues(alpha: 0.55)
                    : AppBrand.paleMint,
                borderRadius: BorderRadius.circular(12),
              ),
              child: Row(
                children: [
                  Expanded(
                    child: Text(
                      'Quick checklist',
                      style: Theme.of(context).textTheme.labelMedium?.copyWith(
                            fontWeight: FontWeight.w700,
                            color: scheme.onSurfaceVariant,
                          ),
                    ),
                  ),
                  Icon(
                    Icons.checklist_rounded,
                    size: 18,
                    color: scheme.onSurfaceVariant,
                  ),
                ],
              ),
            ),
            const SizedBox(height: 8),
            async.when(
              skipLoadingOnReload: true,
              loading: () => const Padding(
                padding: EdgeInsets.symmetric(vertical: 16),
                child: Center(child: CircularProgressIndicator()),
              ),
              error: (e, _) => Text(
                'Could not load groceries: $e',
                style: Theme.of(context).textTheme.bodySmall,
              ),
              data: (items) {
                if (items.isEmpty) {
                  return Padding(
                    padding: const EdgeInsets.only(bottom: 8),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'No items on your list yet.',
                          style: Theme.of(context).textTheme.bodySmall?.copyWith(
                                color: scheme.onSurfaceVariant,
                              ),
                        ),
                        const SizedBox(height: 12),
                        Align(
                          child: FilledButton(
                            onPressed: () => context.go('/grocery'),
                            child: const Text('ADD ITEMS'),
                          ),
                        ),
                      ],
                    ),
                  );
                }

                const openPreviewLimit = 5;
                const purchasedPreviewLimit = 2;
                final open =
                    items.where((i) => !i.isDone).toList(growable: false);
                final done = items.where((i) => i.isDone).toList(growable: false);
                final openPreview =
                    open.take(openPreviewLimit).toList(growable: false);
                final purchasedPreview =
                    done.take(purchasedPreviewLimit).toList(growable: false);
                final remainingPurchasedCount =
                    done.length - purchasedPreview.length;
                final purchasedCount = done.length;
                return Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    if (purchasedCount > 0) ...[
                      Wrap(
                        spacing: 8,
                        runSpacing: 8,
                        alignment: WrapAlignment.spaceBetween,
                        crossAxisAlignment: WrapCrossAlignment.center,
                        children: [
                          _HomeCountPill(
                            label: '${open.length} to buy',
                            icon: Icons.shopping_cart_outlined,
                          ),
                          _HomeCountPill(
                            label: '$purchasedCount purchased',
                            icon: Icons.check_circle_outline_rounded,
                          ),
                        ],
                      ),
                      const SizedBox(height: 8),
                      Align(
                        alignment: Alignment.centerLeft,
                        child: TextButton.icon(
                          onPressed: () =>
                              _promptClearPurchasedFromHome(context, ref),
                          style: TextButton.styleFrom(
                            visualDensity: VisualDensity.compact,
                          ),
                          icon: const Icon(Icons.done_all_outlined, size: 18),
                          label: Text('Clear $purchasedCount purchased'),
                        ),
                      ),
                      const SizedBox(height: 2),
                    ],
                    if (openPreview.isNotEmpty) ...[
                      if (purchasedCount > 0)
                        Padding(
                          padding: const EdgeInsets.only(bottom: 4),
                          child: Text(
                            'To buy',
                            style: Theme.of(context)
                                .textTheme
                                .labelMedium
                                ?.copyWith(
                                  color: scheme.onSurfaceVariant,
                                  fontWeight: FontWeight.w700,
                                ),
                          ),
                        ),
                      for (final item in openPreview)
                        Padding(
                          padding: const EdgeInsets.symmetric(vertical: 4),
                          child: Row(
                            crossAxisAlignment: CrossAxisAlignment.center,
                            children: [
                              SizedBox(
                                width: 40,
                                height: 40,
                                child: IconButton(
                                  padding: EdgeInsets.zero,
                                  alignment: Alignment.center,
                                  tooltip: item.isDone
                                      ? 'Mark as not purchased'
                                      : 'Mark as purchased',
                                  onPressed: () =>
                                      _toggleGroceryItemStatus(ref, item),
                                  icon: Icon(
                                    item.isDone
                                        ? Icons.check_circle_rounded
                                        : Icons.circle_outlined,
                                    size: 22,
                                    color: item.isDone
                                        ? scheme.primary
                                        : scheme.onSurfaceVariant
                                            .withValues(alpha: 0.55),
                                  ),
                                ),
                              ),
                              const SizedBox(width: 6),
                              Expanded(
                                child: InkWell(
                                  onTap: () => context.go('/grocery'),
                                  borderRadius: BorderRadius.circular(8),
                                  child: Padding(
                                    padding: const EdgeInsets.symmetric(
                                      vertical: 4,
                                    ),
                                    child: Text(
                                      _formatGrocerySnippetLine(item),
                                      style: Theme.of(context)
                                          .textTheme
                                          .bodyMedium
                                          ?.copyWith(
                                            color: scheme.onSurface.withValues(
                                              alpha: item.isDone ? 0.5 : 0.88,
                                            ),
                                            decoration: item.isDone
                                                ? TextDecoration.lineThrough
                                                : null,
                                            decorationColor: scheme.onSurface
                                                .withValues(alpha: 0.45),
                                          ),
                                    ),
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                    ],
                    if (purchasedPreview.isNotEmpty) ...[
                      Padding(
                        padding: const EdgeInsets.only(top: 2, bottom: 4),
                        child: Text(
                          'Purchased',
                          style:
                              Theme.of(context).textTheme.labelMedium?.copyWith(
                                    color: scheme.onSurfaceVariant,
                                    fontWeight: FontWeight.w700,
                                  ),
                        ),
                      ),
                      for (final item in purchasedPreview)
                        Padding(
                          padding: const EdgeInsets.symmetric(vertical: 4),
                          child: Row(
                            crossAxisAlignment: CrossAxisAlignment.center,
                            children: [
                              SizedBox(
                                width: 40,
                                height: 40,
                                child: IconButton(
                                  padding: EdgeInsets.zero,
                                  alignment: Alignment.center,
                                  tooltip: item.isDone
                                      ? 'Mark as not purchased'
                                      : 'Mark as purchased',
                                  onPressed: () =>
                                      _toggleGroceryItemStatus(ref, item),
                                  icon: Icon(
                                    item.isDone
                                        ? Icons.check_circle_rounded
                                        : Icons.circle_outlined,
                                    size: 22,
                                    color: item.isDone
                                        ? scheme.primary
                                        : scheme.onSurfaceVariant
                                            .withValues(alpha: 0.55),
                                  ),
                                ),
                              ),
                              const SizedBox(width: 6),
                              Expanded(
                                child: InkWell(
                                  onTap: () => context.go('/grocery'),
                                  borderRadius: BorderRadius.circular(8),
                                  child: Padding(
                                    padding: const EdgeInsets.symmetric(
                                      vertical: 4,
                                    ),
                                    child: Text(
                                      _formatGrocerySnippetLine(item),
                                      style: Theme.of(context)
                                          .textTheme
                                          .bodyMedium
                                          ?.copyWith(
                                            color: scheme.onSurface.withValues(
                                              alpha: item.isDone ? 0.5 : 0.88,
                                            ),
                                            decoration: item.isDone
                                                ? TextDecoration.lineThrough
                                                : null,
                                            decorationColor: scheme.onSurface
                                                .withValues(alpha: 0.45),
                                          ),
                                    ),
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                      if (remainingPurchasedCount > 0)
                        Padding(
                          padding: const EdgeInsets.fromLTRB(46, 2, 0, 0),
                          child: Text(
                            '+$remainingPurchasedCount more purchased',
                            style: Theme.of(context)
                                .textTheme
                                .bodySmall
                                ?.copyWith(color: scheme.onSurfaceVariant),
                          ),
                        ),
                    ],
                    const SizedBox(height: 8),
                    Center(
                      child: FilledButton(
                        onPressed: () => context.go('/grocery'),
                        style: FilledButton.styleFrom(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 20,
                            vertical: 12,
                          ),
                          shape: const StadiumBorder(),
                        ),
                        child: Text(
                          'VIEW FULL CHECKLIST (${items.length})',
                          style: Theme.of(context).textTheme.labelLarge?.copyWith(
                                fontWeight: FontWeight.w700,
                                letterSpacing: 0.4,
                              ),
                        ),
                      ),
                    ),
                  ],
                );
              },
            ),
          ],
        ),
      ),
    );
  }
}

class _HomeHeader extends StatelessWidget {
  const _HomeHeader();

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final now = DateTime.now();
    final weekday = switch (now.weekday) {
      DateTime.monday => 'Monday',
      DateTime.tuesday => 'Tuesday',
      DateTime.wednesday => 'Wednesday',
      DateTime.thursday => 'Thursday',
      DateTime.friday => 'Friday',
      DateTime.saturday => 'Saturday',
      DateTime.sunday => 'Sunday',
      _ => 'Today',
    };
    return Container(
      padding: const EdgeInsets.all(AppSpacing.md),
      decoration: BoxDecoration(
        borderRadius: AppRadius.md,
        gradient: isDark
            ? AppBrand.headerGradientDark
            : AppBrand.headerGradient,
        boxShadow: AppShadows.soft,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(
                Icons.wb_sunny_outlined,
                color: AppBrand.offWhite.withValues(alpha: 0.95),
              ),
              const SizedBox(width: AppSpacing.xs),
              Text(
                '$weekday Focus',
                style: Theme.of(context).textTheme.titleSmall?.copyWith(
                      color: AppBrand.offWhite,
                      fontWeight: FontWeight.w800,
                    ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _HomeCountPill extends StatelessWidget {
  const _HomeCountPill({
    required this.label,
    required this.icon,
  });

  final String label;
  final IconData icon;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: isDark
            ? scheme.surfaceContainerHighest.withValues(alpha: 0.65)
            : AppBrand.paleMint,
        borderRadius: BorderRadius.circular(999),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 14, color: scheme.onSurfaceVariant),
          const SizedBox(width: 6),
          Text(
            label,
            style: Theme.of(context).textTheme.labelSmall?.copyWith(
                  fontWeight: FontWeight.w700,
                ),
          ),
        ],
      ),
    );
  }
}

double _groceryParseQuantity(String? raw, {double fallback = 1}) {
  final normalized = raw?.trim().replaceAll(',', '.');
  final parsed = normalized == null ? null : double.tryParse(normalized);
  if (parsed == null || parsed <= 0) return fallback;
  return parsed;
}

String _groceryFormatQuantity(double value) {
  if (value == value.roundToDouble()) {
    return value.toInt().toString();
  }
  return value.toStringAsFixed(1);
}

String _formatGrocerySnippetLine(GroceryItem item) {
  final q = item.quantity?.trim();
  if (q == null || q.isEmpty) return item.name;
  final qtyVal = _groceryParseQuantity(q, fallback: 1);
  final qtyStr = item.unit == null || item.unit!.trim().isEmpty
      ? _groceryFormatQuantity(qtyVal)
      : '${_groceryFormatQuantity(qtyVal)} ${item.unit!.trim()}';
  return '${item.name} ($qtyStr)';
}
