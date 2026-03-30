import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:plateplan/core/models/app_models.dart';
import 'package:plateplan/core/planner_slot_labels.dart';
import 'package:plateplan/core/theme/app_brand.dart';
import 'package:plateplan/features/planner/presentation/planner_day_summary_tile.dart';

/// Magazine-style day cell for the planner grid (reference UI).
///
/// When [onTap] is null, the card is display-only (no inner [InkWell]); use a
/// parent [InkWell]/[GestureDetector] with [HitTestBehavior.opaque] so empty
/// days still receive taps reliably.
class PlannerMagazineDayCard extends StatelessWidget {
  const PlannerMagazineDayCard({
    super.key,
    required this.date,
    required this.isToday,
    required this.daySlots,
    required this.recipes,
    required this.maxVisibleSlots,
    this.onTap,
  });

  final DateTime date;
  final bool isToday;
  final List<MealPlanSlot> daySlots;
  final List<Recipe> recipes;
  final int maxVisibleSlots;
  final VoidCallback? onTap;

  static const BorderRadius cardRadius = BorderRadius.all(Radius.circular(20));

  static const Color _lightCard = Color(0xFFFFFFFF);
  /// Matches [DiscoverShellScaffold] header strip ([AppBrand.paleMint]).
  static const Color _lightTodayFill = AppBrand.paleMint;
  /// Teal ring aligned with shell avatar / notification accent ([AppBrand.deepTeal]).
  static final Color _lightTodayBorder =
      AppBrand.deepTeal.withValues(alpha: 0.5);
  static const Color _lightTodayStar = AppBrand.deepTeal;
  static const Color _lightMuted = Color(0xFF9AA3B2);
  static const Color _lightBody = Color(0xFF5C6578);
  static const Color _diningPillBg = Color(0xFFE8F5E9);
  static const Color _diningPillFg = Color(0xFF2E5C3A);

  static bool _isDiningOut(MealPlanSlot slot) {
    final t = slot.mealText?.trim().toLowerCase() ?? '';
    return t.contains('dining out');
  }

  static IconData _iconForMealLabel(String mealLabel) {
    switch (mealLabel.toLowerCase()) {
      case 'breakfast':
      case 'brunch':
        return Icons.free_breakfast_rounded;
      case 'lunch':
        return Icons.lunch_dining_rounded;
      case 'dinner':
      case 'supper':
        return Icons.dinner_dining_rounded;
      case 'snack':
        return Icons.cookie_rounded;
      default:
        return Icons.restaurant_menu_rounded;
    }
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final isDark = Theme.of(context).brightness == Brightness.dark;

    final fill = isDark
        ? (isToday ? scheme.primaryContainer.withValues(alpha: 0.35) : scheme.surfaceContainerHigh)
        : (isToday ? _lightTodayFill : _lightCard);
    final borderColor = isDark
        ? (isToday ? scheme.primary : scheme.outlineVariant)
        : (isToday ? _lightTodayBorder : const Color(0xFFE8EAEF));
    final borderW = isToday ? 1.5 : 1.0;
    final weekdayColor =
        isDark ? scheme.onSurfaceVariant : _lightMuted;
    final dayNumColor =
        isDark ? scheme.onSurface : const Color(0xFF2E3A59);
    final bodyColor = isDark ? scheme.onSurface.withValues(alpha: 0.88) : _lightBody;
    final starColor = isDark ? scheme.primary : _lightTodayStar;

    final visible = daySlots.take(maxVisibleSlots).toList();
    final extra = daySlots.length - visible.length;

    final inkChild = Ink(
      width: double.infinity,
      height: double.infinity,
      decoration: BoxDecoration(
        color: fill,
        borderRadius: cardRadius,
        border: Border.all(color: borderColor, width: borderW),
        boxShadow: [
          BoxShadow(
            color: scheme.shadow.withValues(alpha: isDark ? 0.12 : 0.06),
            blurRadius: 12,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: ClipRRect(
        borderRadius: cardRadius,
        child: Stack(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(12, 12, 12, 10),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              DateFormat('EEE').format(date).toUpperCase(),
                              style: Theme.of(context)
                                  .textTheme
                                  .labelSmall
                                  ?.copyWith(
                                    letterSpacing: 0.8,
                                    fontWeight: FontWeight.w600,
                                    color: weekdayColor,
                                  ),
                            ),
                            const SizedBox(height: 2),
                            Text(
                              '${date.day}',
                              style: Theme.of(context)
                                  .textTheme
                                  .headlineMedium
                                  ?.copyWith(
                                    fontWeight: FontWeight.w800,
                                    height: 1.05,
                                    color: dayNumColor,
                                  ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  Expanded(
                    child: daySlots.isEmpty
                        ? Align(
                            alignment: Alignment.topLeft,
                            child: Text(
                              'NO SLOTS',
                              style: Theme.of(context)
                                  .textTheme
                                  .labelSmall
                                  ?.copyWith(
                                    color: weekdayColor,
                                    fontStyle: FontStyle.italic,
                                    fontWeight: FontWeight.w600,
                                  ),
                            ),
                          )
                        : SingleChildScrollView(
                            physics: const BouncingScrollPhysics(),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                for (final slot in visible)
                                  Padding(
                                    padding: const EdgeInsets.only(bottom: 8),
                                    child: _slotRow(
                                      context,
                                      slot: slot,
                                      bodyColor: bodyColor,
                                      mutedColor: weekdayColor,
                                    ),
                                  ),
                                if (extra > 0)
                                  Text(
                                    '+$extra more',
                                    style: Theme.of(context)
                                        .textTheme
                                        .labelSmall
                                        ?.copyWith(
                                          color: weekdayColor,
                                          fontStyle: FontStyle.italic,
                                          fontWeight: FontWeight.w600,
                                        ),
                                  ),
                              ],
                            ),
                          ),
                  ),
                ],
              ),
            ),
            if (isToday)
              Positioned(
                top: 8,
                right: 8,
                child: Icon(
                  Icons.star_rounded,
                  size: 18,
                  color: starColor,
                ),
              ),
          ],
        ),
      ),
    );

    if (onTap == null) {
      return inkChild;
    }
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: cardRadius,
        child: inkChild,
      ),
    );
  }

  Widget _slotRow(
    BuildContext context, {
    required MealPlanSlot slot,
    required Color bodyColor,
    required Color mutedColor,
  }) {
    final label = plannerSlotDisplayLabel(daySlots, slot);

    if (_isDiningOut(slot)) {
      return Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
        decoration: BoxDecoration(
          color: Theme.of(context).brightness == Brightness.dark
              ? Theme.of(context).colorScheme.primaryContainer.withValues(alpha: 0.5)
              : _diningPillBg,
          borderRadius: BorderRadius.circular(999),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              Icons.restaurant_rounded,
              size: 16,
              color: Theme.of(context).brightness == Brightness.dark
                  ? Theme.of(context).colorScheme.onPrimaryContainer
                  : _diningPillFg,
            ),
            const SizedBox(width: 6),
            Flexible(
              child: Text(
                'DINING OUT',
                style: Theme.of(context).textTheme.labelSmall?.copyWith(
                      fontWeight: FontWeight.w800,
                      letterSpacing: 0.6,
                      color: Theme.of(context).brightness == Brightness.dark
                          ? Theme.of(context).colorScheme.onPrimaryContainer
                          : _diningPillFg,
                    ),
              ),
            ),
          ],
        ),
      );
    }

    if (!slot.hasPlannedContent) {
      return Text(
        'NO ${label.toUpperCase()} PLANNED',
        style: Theme.of(context).textTheme.labelSmall?.copyWith(
              color: mutedColor,
              fontStyle: FontStyle.italic,
              fontWeight: FontWeight.w600,
              letterSpacing: 0.3,
            ),
      );
    }

    final line = plannerSlotPrimarySummaryLine(slot, recipes);
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(
          _iconForMealLabel(slot.mealLabel),
          size: 18,
          color: bodyColor.withValues(alpha: 0.85),
        ),
        const SizedBox(width: 8),
        Expanded(
          child: Text(
            line,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: Theme.of(context).textTheme.labelMedium?.copyWith(
                  height: 1.25,
                  fontWeight: FontWeight.w500,
                  color: bodyColor,
                ),
          ),
        ),
      ],
    );
  }
}
