import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:collection/collection.dart';
import 'package:intl/intl.dart';
import 'package:plateplan/core/ui/app_surface.dart';
import 'package:plateplan/core/ui/section_card.dart';
import 'package:plateplan/core/theme/design_tokens.dart';
import 'package:plateplan/features/household/data/household_providers.dart';
import 'package:plateplan/features/home/presentation/home_outlook_day_card.dart';
import 'package:plateplan/features/profile/data/profile_providers.dart';
import 'package:plateplan/features/recipes/data/recipes_repository.dart';
import 'package:plateplan/features/grocery/data/grocery_repository.dart';
import 'package:plateplan/features/planner/data/planner_repository.dart';
import 'package:plateplan/core/planner_slot_labels.dart';
import 'package:plateplan/features/planner/presentation/planner_day_summary_tile.dart';
import 'package:plateplan/core/models/app_models.dart';
import 'package:plateplan/core/planner_week_mapping.dart';

class HomeScreen extends ConsumerWidget {
  const HomeScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final planner = ref.watch(plannerSlotsProvider);
    final pendingInvites = ref.watch(pendingHouseholdInvitesProvider);
    final pendingInviteCount = pendingInvites.valueOrNull?.length ?? 0;
    return Scaffold(
      appBar: AppBar(
        title: const Text('Leckerly'),
        actions: [
          IconButton(
            tooltip: 'Profile',
            onPressed: () => context.go('/profile'),
            icon: pendingInviteCount > 0
                ? Badge(
                    label: Text('$pendingInviteCount'),
                    child: const Icon(Icons.person_outline),
                  )
                : const Icon(Icons.person_outline),
          ),
        ],
      ),
      body: AppSurface(
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(12, 10, 12, 24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              _HomeHeader(plannerSlots: planner),
              const SizedBox(height: 16),
              const _HomeThreeDayOutlook(),
              const SizedBox(height: 16),
              const _HomeGrocerySnippet(),
            ],
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
      subtitle: 'Your curated culinary schedule',
      titleTrailing: TextButton(
        onPressed: () => context.go('/planner'),
        style: TextButton.styleFrom(
          foregroundColor: Theme.of(context).colorScheme.primary,
          textStyle: Theme.of(context).textTheme.labelLarge?.copyWith(
                fontWeight: FontWeight.w800,
                letterSpacing: 0.6,
              ),
        ),
        child: const Text('VIEW FULL PLAN'),
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
              return Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  for (var i = 0; i < dates.length; i++) ...[
                    if (i > 0) const SizedBox(height: 12),
                    HomeOutlookDayCard(
                      date: dates[i],
                      outlookIndex: i,
                      daySlots: slots
                          .where((s) =>
                              plannerDateOnly(calendarDateForSlot(s)) ==
                              plannerDateOnly(dates[i]))
                          .sorted(
                              (a, b) => a.slotOrder.compareTo(b.slotOrder))
                          .toList(),
                      recipes: recipes,
                      onTap: () {
                        final daySlots = slots
                            .where((s) =>
                                plannerDateOnly(calendarDateForSlot(s)) ==
                                plannerDateOnly(dates[i]))
                            .sorted(
                                (a, b) => a.slotOrder.compareTo(b.slotOrder))
                            .toList();
                        _showHomeOutlookDaySheet(
                          context: context,
                          ref: ref,
                          date: dates[i],
                          daySlots: daySlots,
                          recipes: recipes,
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

Future<void> _showHomeOutlookDaySheet({
  required BuildContext context,
  required WidgetRef ref,
  required DateTime date,
  required List<MealPlanSlot> daySlots,
  required List<Recipe> recipes,
}) async {
  final sortedSlots = [...daySlots]..sort((a, b) => a.slotOrder.compareTo(b.slotOrder));
  final header = DateFormat('EEEE, MMM d').format(date);

  await showModalBottomSheet<void>(
    context: context,
    showDragHandle: true,
    isScrollControlled: true,
    builder: (sheetContext) {
      return SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(12, 0, 12, 12),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(4, 8, 4, 6),
                child: Text(
                  header,
                  style: Theme.of(sheetContext).textTheme.titleLarge?.copyWith(
                        fontWeight: FontWeight.w800,
                      ),
                ),
              ),
              if (sortedSlots.isEmpty)
                Padding(
                  padding: const EdgeInsets.fromLTRB(4, 8, 4, 12),
                  child: Text(
                    'Nothing planned for this day.',
                    style: Theme.of(sheetContext).textTheme.bodyMedium?.copyWith(
                          color: Theme.of(sheetContext).colorScheme.onSurfaceVariant,
                        ),
                  ),
                )
              else
                Flexible(
                  child: ListView.separated(
                    shrinkWrap: true,
                    itemCount: sortedSlots.length,
                    separatorBuilder: (_, __) => const SizedBox(height: 4),
                    itemBuilder: (ctx, index) {
                      final slot = sortedSlots[index];
                      final line = plannerSlotPrimarySummaryLine(slot, recipes);
                      final hasRecipe = (slot.recipeId?.trim().isNotEmpty ?? false);
                      return ListTile(
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(10),
                        ),
                        tileColor: Theme.of(ctx)
                            .colorScheme
                            .surfaceContainerHighest
                            .withValues(alpha: 0.45),
                        title: Text(plannerSlotDisplayLabel(sortedSlots, slot)),
                        subtitle: Text(
                          line,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                        ),
                        trailing: Icon(
                          hasRecipe
                              ? Icons.chevron_right_rounded
                              : Icons.horizontal_rule_rounded,
                        ),
                        enabled: hasRecipe,
                        onTap: hasRecipe
                            ? () {
                                final recipeId = slot.recipeId!.trim();
                                Navigator.of(sheetContext).pop();
                                context.push('/cooking/$recipeId');
                              }
                            : null,
                      );
                    },
                  ),
                ),
              const SizedBox(height: 8),
              Align(
                alignment: Alignment.centerRight,
                child: TextButton.icon(
                  onPressed: () {
                    Navigator.of(sheetContext).pop();
                    focusPlannerOnCalendarDate(ref, date);
                    context.go('/planner');
                  },
                  icon: const Icon(Icons.calendar_view_week_rounded),
                  label: const Text('View in planner'),
                ),
              ),
            ],
          ),
        ),
      );
    },
  );
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

  static const Color _lightCream = Color(0xFFF5F0E8);

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final scheme = Theme.of(context).colorScheme;
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final async = ref.watch(groceryItemsProvider);

    return Container(
      decoration: BoxDecoration(
        color: isDark ? scheme.surfaceContainerHigh : _lightCream,
        borderRadius: AppRadius.md,
        boxShadow: AppShadows.soft,
      ),
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  child: Text(
                    'Grocery Snippet',
                    style: Theme.of(context).textTheme.titleMedium?.copyWith(
                          fontWeight: FontWeight.w700,
                        ),
                  ),
                ),
                IconButton(
                  tooltip: 'Open grocery list',
                  onPressed: () => context.go('/grocery'),
                  icon: Icon(
                    Icons.shopping_basket_rounded,
                    color: scheme.onSurfaceVariant,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 4),
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
                          child: FilledButton.tonal(
                            onPressed: () => context.go('/grocery'),
                            child: const Text('ADD ITEMS'),
                          ),
                        ),
                      ],
                    ),
                  );
                }

                final open =
                    items.where((i) => !i.isDone).toList(growable: false);
                final done = items.where((i) => i.isDone).toList(growable: false);
                final preview = [...open, ...done].take(4).toList();
                final purchasedCount = done.length;
                return Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    if (purchasedCount > 0) ...[
                      Align(
                        alignment: Alignment.centerRight,
                        child: TextButton.icon(
                          onPressed: () =>
                              _promptClearPurchasedFromHome(context, ref),
                          icon: const Icon(Icons.done_all_outlined, size: 20),
                          label: Text('Clear $purchasedCount purchased'),
                        ),
                      ),
                      const SizedBox(height: 6),
                    ],
                    for (final item in preview)
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
                    const SizedBox(height: 8),
                    Center(
                      child: FilledButton.tonal(
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
  const _HomeHeader({required this.plannerSlots});

  final AsyncValue<List<MealPlanSlot>> plannerSlots;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
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
    final statusLine = plannerSlots.when(
      data: (slots) {
        final count = _filledTodaySlots(slots).length;
        if (count == 0) {
          return 'No meals planned yet. Start one for tonight.';
        }
        if (count == 1) return '1 meal planned for today.';
        return '$count meals planned for today.';
      },
      loading: () => 'Checking today’s plan…',
      error: (_, __) => 'Could not load today’s meals.',
    );

    return Container(
      padding: const EdgeInsets.all(AppSpacing.md),
      decoration: BoxDecoration(
        borderRadius: AppRadius.md,
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            scheme.primaryContainer,
            scheme.tertiaryContainer,
          ],
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(
                Icons.wb_sunny_outlined,
                color: scheme.onPrimaryContainer,
              ),
              const SizedBox(width: AppSpacing.xs),
              Text(
                '$weekday focus',
                style: Theme.of(context).textTheme.titleSmall?.copyWith(
                      color: scheme.onPrimaryContainer,
                      fontWeight: FontWeight.w700,
                    ),
              ),
            ],
          ),
          const SizedBox(height: AppSpacing.xs),
          Text(
            'Home',
            style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                  color: scheme.onPrimaryContainer,
                  fontWeight: FontWeight.w900,
                ),
          ),
          const SizedBox(height: AppSpacing.xs),
          Text(
            statusLine,
            style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                  color: scheme.onPrimaryContainer.withValues(alpha: 0.9),
                ),
          ),
        ],
      ),
    );
  }
}

/// True when [slot] falls on today's calendar date (matches planner mapping).
bool _isSlotOnToday(MealPlanSlot slot) {
  final today = plannerDateOnly(DateTime.now());
  return plannerDateOnly(calendarDateForSlot(slot)) == today;
}

Iterable<MealPlanSlot> _todaySlots(Iterable<MealPlanSlot> slots) =>
    slots.where(_isSlotOnToday);

Iterable<MealPlanSlot> _filledTodaySlots(Iterable<MealPlanSlot> slots) =>
    _todaySlots(slots).where((s) => s.hasPlannedContent);

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
