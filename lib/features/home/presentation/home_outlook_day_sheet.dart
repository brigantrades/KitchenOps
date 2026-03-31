import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';
import 'package:plateplan/core/models/app_models.dart';
import 'package:plateplan/core/planner_slot_labels.dart';
import 'package:plateplan/core/theme/app_brand.dart';
import 'package:plateplan/core/theme/design_tokens.dart';
import 'package:plateplan/features/auth/data/auth_providers.dart';
import 'package:plateplan/features/home/presentation/home_outlook_day_card.dart';
import 'package:plateplan/features/household/data/household_providers.dart';
import 'package:plateplan/features/planner/data/planner_repository.dart';
import 'package:plateplan/features/planner/presentation/planner_day_summary_tile.dart';
import 'package:plateplan/features/planner/presentation/planner_screen.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

/// Bottom sheet when tapping a day on Home → 3-Day Outlook (branded, not flat gray).
Future<void> showHomeOutlookDayDetailSheet({
  required BuildContext context,
  required WidgetRef ref,
  required DateTime date,
  required List<MealPlanSlot> daySlots,
  required List<Recipe> recipes,
}) async {
  final sortedSlots = [...daySlots]..sort((a, b) => a.slotOrder.compareTo(b.slotOrder));
  final members =
      ref.read(householdMembersProvider).valueOrNull ?? const [];
  final activeMembers = members
      .where((m) => m.status == HouseholdMemberStatus.active)
      .toList();
  final showMemberAssignment =
      ref.read(hasSharedHouseholdProvider).valueOrNull ?? false;
  final user = ref.read(currentUserProvider);

  await showModalBottomSheet<void>(
    context: context,
    showDragHandle: false,
    isScrollControlled: true,
    backgroundColor: Colors.transparent,
    useSafeArea: true,
    builder: (sheetContext) {
      void goToPlannerForDay() {
        Navigator.of(sheetContext).pop();
        focusPlannerOnCalendarDate(ref, date);
        context.go('/planner');
      }

      final scheme = Theme.of(sheetContext).colorScheme;
      final isDark = Theme.of(sheetContext).brightness == Brightness.dark;
      final ctaColor = isDark ? scheme.primary : AppBrand.deepTeal;

      final topGradient = isDark
          ? const LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [
                Color(0xFF1A2E2C),
                Color(0xFF152A28),
              ],
            )
          : LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [
                AppBrand.paleMint,
                AppBrand.offWhite,
              ],
            );

      return DraggableScrollableSheet(
        expand: false,
        initialChildSize: 0.72,
        minChildSize: 0.42,
        maxChildSize: 0.92,
        builder: (context, scrollController) {
          return ClipRRect(
            borderRadius: const BorderRadius.vertical(top: Radius.circular(28)),
            child: DecoratedBox(
              decoration: BoxDecoration(
                gradient: topGradient,
                boxShadow: AppShadows.floating,
              ),
              child: SafeArea(
                top: false,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Center(
                      child: Padding(
                        padding: const EdgeInsets.only(top: 10, bottom: 6),
                        child: Container(
                          width: 40,
                          height: 4,
                          decoration: BoxDecoration(
                            color: scheme.onSurfaceVariant
                                .withValues(alpha: isDark ? 0.45 : 0.35),
                            borderRadius: BorderRadius.circular(999),
                          ),
                        ),
                      ),
                    ),
                    Padding(
                      padding: const EdgeInsets.fromLTRB(16, 4, 16, 12),
                      child: _OutlookSheetHeader(date: date),
                    ),
                    Expanded(
                      child: sortedSlots.isEmpty
                          ? ListView(
                              controller: scrollController,
                              padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
                              children: [
                                _EmptyDayCallout(
                                  scheme: scheme,
                                  isDark: isDark,
                                  ctaColor: ctaColor,
                                  onPlan: goToPlannerForDay,
                                ),
                              ],
                            )
                          : ListView.separated(
                              controller: scrollController,
                              padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
                              itemCount: sortedSlots.length,
                              separatorBuilder: (_, __) =>
                                  const SizedBox(height: 12),
                              itemBuilder: (ctx, index) {
                                final slot = sortedSlots[index];
                                if (!slot.hasPlannedContent) {
                                  return _ChooseMealCard(
                                    slot: slot,
                                    sortedSlots: sortedSlots,
                                    scheme: scheme,
                                    isDark: isDark,
                                    ctaColor: ctaColor,
                                    user: user,
                                    onChoose: user == null
                                        ? null
                                        : () {
                                            unawaited(
                                              openSlotMealPlanEditorFromHome(
                                                context,
                                                ref,
                                                slot: slot,
                                                daySlots: sortedSlots,
                                                recipes: recipes,
                                                activeMembers: activeMembers,
                                                currentUserId: user.id,
                                                showMemberAssignment:
                                                    showMemberAssignment,
                                              ),
                                            );
                                          },
                                  );
                                }
                                return _PlannedMealCard(
                                  slot: slot,
                                  sortedSlots: sortedSlots,
                                  recipes: recipes,
                                  scheme: scheme,
                                  isDark: isDark,
                                  onTap: () {
                                    final hasRecipe = (slot.recipeId
                                            ?.trim()
                                            .isNotEmpty ??
                                        false);
                                    if (hasRecipe) {
                                      final recipeId = slot.recipeId!.trim();
                                      Navigator.of(sheetContext).pop();
                                      context.push('/cooking/$recipeId');
                                    } else {
                                      if (user == null) return;
                                      unawaited(
                                        openSlotMealPlanEditorFromHome(
                                          context,
                                          ref,
                                          slot: slot,
                                          daySlots: sortedSlots,
                                          recipes: recipes,
                                          activeMembers: activeMembers,
                                          currentUserId: user.id,
                                          showMemberAssignment:
                                              showMemberAssignment,
                                        ),
                                      );
                                    }
                                  },
                                );
                              },
                            ),
                    ),
                    Padding(
                      padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
                      child: FilledButton.icon(
                        onPressed: goToPlannerForDay,
                        style: FilledButton.styleFrom(
                          backgroundColor: AppBrand.deepTeal,
                          foregroundColor: AppBrand.offWhite,
                          padding: const EdgeInsets.symmetric(
                            horizontal: 20,
                            vertical: 14,
                          ),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(16),
                          ),
                          elevation: 0,
                        ),
                        icon: const Icon(Icons.calendar_view_week_rounded),
                        label: const Text('View in planner'),
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
  );
}

class _OutlookSheetHeader extends StatelessWidget {
  const _OutlookSheetHeader({required this.date});

  final DateTime date;

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Container(
      decoration: BoxDecoration(
        gradient: isDark ? AppBrand.headerGradientDark : AppBrand.headerGradient,
        borderRadius: BorderRadius.circular(20),
        boxShadow: AppShadows.soft,
      ),
      padding: const EdgeInsets.fromLTRB(18, 16, 18, 16),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              color: AppBrand.offWhite.withValues(alpha: 0.18),
              borderRadius: BorderRadius.circular(14),
            ),
            child: Icon(
              Icons.restaurant_menu_rounded,
              color: AppBrand.offWhite.withValues(alpha: 0.95),
              size: 24,
            ),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  DateFormat('EEEE').format(date).toUpperCase(),
                  style: Theme.of(context).textTheme.labelSmall?.copyWith(
                        color: AppBrand.offWhite.withValues(alpha: 0.88),
                        fontWeight: FontWeight.w700,
                        letterSpacing: 1.1,
                      ),
                ),
                const SizedBox(height: 4),
                Text(
                  DateFormat('MMM d, yyyy').format(date),
                  style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                        color: AppBrand.offWhite,
                        fontWeight: FontWeight.w800,
                        height: 1.05,
                      ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _EmptyDayCallout extends StatelessWidget {
  const _EmptyDayCallout({
    required this.scheme,
    required this.isDark,
    required this.ctaColor,
    required this.onPlan,
  });

  final ColorScheme scheme;
  final bool isDark;
  final Color ctaColor;
  final VoidCallback onPlan;

  @override
  Widget build(BuildContext context) {
    final fill = isDark
        ? scheme.surfaceContainerHighest.withValues(alpha: 0.55)
        : AppBrand.paleMint.withValues(alpha: 0.85);
    final border = isDark
        ? scheme.outlineVariant.withValues(alpha: 0.4)
        : AppBrand.mutedAqua.withValues(alpha: 0.9);

    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: fill,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: border),
        boxShadow: isDark ? null : AppShadows.soft,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.spa_outlined, color: ctaColor, size: 22),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  'Nothing planned yet',
                  style: Theme.of(context).textTheme.titleSmall?.copyWith(
                        fontWeight: FontWeight.w800,
                        color: scheme.onSurface,
                      ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            'Add meals in the planner or tap below to jump there now.',
            style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                  color: scheme.onSurfaceVariant,
                  height: 1.35,
                ),
          ),
          const SizedBox(height: 14),
          Semantics(
            hint: 'Opens the planner for this day',
            child: Material(
              color: Colors.transparent,
              child: InkWell(
                onTap: onPlan,
                borderRadius: BorderRadius.circular(14),
                child: Ink(
                  decoration: BoxDecoration(
                    color: isDark
                        ? scheme.primary.withValues(alpha: 0.22)
                        : AppBrand.offWhite,
                    borderRadius: BorderRadius.circular(14),
                    border: Border.all(color: ctaColor.withValues(alpha: 0.45)),
                  ),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 14,
                      vertical: 12,
                    ),
                    child: Row(
                      children: [
                        Icon(Icons.edit_calendar_outlined, color: ctaColor),
                        const SizedBox(width: 10),
                        Expanded(
                          child: Text(
                            'Plan this day',
                            style: Theme.of(context)
                                .textTheme
                                .labelLarge
                                ?.copyWith(
                                  fontWeight: FontWeight.w800,
                                  color: ctaColor,
                                ),
                          ),
                        ),
                        Icon(Icons.arrow_forward_rounded, color: ctaColor),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _ChooseMealCard extends StatelessWidget {
  const _ChooseMealCard({
    required this.slot,
    required this.sortedSlots,
    required this.scheme,
    required this.isDark,
    required this.ctaColor,
    required this.user,
    required this.onChoose,
  });

  final MealPlanSlot slot;
  final List<MealPlanSlot> sortedSlots;
  final ColorScheme scheme;
  final bool isDark;
  final Color ctaColor;
  final User? user;
  final VoidCallback? onChoose;

  @override
  Widget build(BuildContext context) {
    final upper = homeOutlookSlotUpperLabel(slot, sortedSlots);
    final border = ctaColor.withValues(alpha: 0.45);
    final fill = isDark
        ? scheme.primary.withValues(alpha: 0.12)
        : AppBrand.paleMint.withValues(alpha: 0.65);

    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onChoose,
        borderRadius: BorderRadius.circular(20),
        child: Ink(
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [
                fill,
                isDark
                    ? scheme.surfaceContainerHighest.withValues(alpha: 0.35)
                    : AppBrand.offWhite,
              ],
            ),
            borderRadius: BorderRadius.circular(20),
            border: Border.all(color: border, width: 1.5),
            boxShadow: isDark ? null : AppShadows.soft,
          ),
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  plannerSlotDisplayLabel(sortedSlots, slot),
                  style: Theme.of(context).textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.w800,
                        color: scheme.onSurface,
                      ),
                ),
                const SizedBox(height: 6),
                Text(
                  'NO $upper PLANNED',
                  style: Theme.of(context).textTheme.labelSmall?.copyWith(
                        color: scheme.onSurfaceVariant,
                        fontStyle: FontStyle.italic,
                        fontWeight: FontWeight.w700,
                        letterSpacing: 0.4,
                      ),
                ),
                const SizedBox(height: 12),
                Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.all(8),
                      decoration: BoxDecoration(
                        color: ctaColor.withValues(alpha: 0.15),
                        shape: BoxShape.circle,
                      ),
                      child: Icon(
                        Icons.add_rounded,
                        size: 20,
                        color: user == null ? scheme.onSurfaceVariant : ctaColor,
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Text(
                        'Choose a meal',
                        style: Theme.of(context).textTheme.titleSmall?.copyWith(
                              fontWeight: FontWeight.w800,
                              color: user == null
                                  ? scheme.onSurfaceVariant
                                  : ctaColor,
                            ),
                      ),
                    ),
                    Icon(
                      Icons.tune_rounded,
                      size: 20,
                      color: scheme.onSurfaceVariant.withValues(alpha: 0.6),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _PlannedMealCard extends StatelessWidget {
  const _PlannedMealCard({
    required this.slot,
    required this.sortedSlots,
    required this.recipes,
    required this.scheme,
    required this.isDark,
    required this.onTap,
  });

  final MealPlanSlot slot;
  final List<MealPlanSlot> sortedSlots;
  final List<Recipe> recipes;
  final ColorScheme scheme;
  final bool isDark;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final line = plannerSlotPrimarySummaryLine(slot, recipes);
    final hasRecipe = (slot.recipeId?.trim().isNotEmpty ?? false);
    final title = plannerSlotDisplayLabel(sortedSlots, slot);

    final cardBg = isDark
        ? scheme.surfaceContainerHigh.withValues(alpha: 0.9)
        : Colors.white;
    final borderColor = isDark
        ? scheme.outlineVariant.withValues(alpha: 0.35)
        : AppBrand.mutedAqua.withValues(alpha: 0.85);

    final iconBg = hasRecipe
        ? AppBrand.tealVibrant.withValues(alpha: 0.22)
        : AppBrand.paleMint.withValues(alpha: 0.95);
    final iconFg =
        hasRecipe ? AppBrand.deepTeal : AppBrand.deepTeal.withValues(alpha: 0.85);

    return Material(
      color: Colors.transparent,
      elevation: 0,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(20),
        child: Ink(
          decoration: BoxDecoration(
            color: cardBg,
            borderRadius: BorderRadius.circular(20),
            border: Border.all(color: borderColor),
            boxShadow: isDark ? null : AppShadows.soft,
          ),
          child: Padding(
            padding: const EdgeInsets.all(14),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: iconBg,
                    borderRadius: BorderRadius.circular(16),
                  ),
                  child: Icon(
                    hasRecipe
                        ? Icons.dinner_dining_rounded
                        : Icons.notes_rounded,
                    color: iconFg,
                    size: 24,
                  ),
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        title,
                        style: Theme.of(context).textTheme.titleSmall?.copyWith(
                              fontWeight: FontWeight.w800,
                              color: scheme.onSurface,
                            ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        line,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                              fontWeight: FontWeight.w600,
                              color: isDark
                                  ? scheme.onSurface.withValues(alpha: 0.92)
                                  : const Color(0xFF1A2E2C),
                              height: 1.25,
                            ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 8),
                Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: AppBrand.paleMint.withValues(alpha: 0.7),
                    shape: BoxShape.circle,
                  ),
                  child: Icon(
                    hasRecipe
                        ? Icons.chevron_right_rounded
                        : Icons.edit_outlined,
                    color: AppBrand.deepTeal,
                    size: 22,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
