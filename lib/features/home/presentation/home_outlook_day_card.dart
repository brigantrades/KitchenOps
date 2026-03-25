import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:plateplan/core/models/app_models.dart';
import 'package:plateplan/core/planner_slot_labels.dart';
import 'package:plateplan/features/planner/presentation/planner_day_summary_tile.dart';

/// Upper label for home outlook rows: prefer meal time from [mealLabel], else
/// [plannerSlotDisplayLabel] uppercased.
String homeOutlookSlotUpperLabel(
  MealPlanSlot slot,
  List<MealPlanSlot> daySlotsSorted,
) {
  final l = slot.mealLabel.toLowerCase().trim();
  switch (l) {
    case 'breakfast':
      return 'BREAKFAST';
    case 'brunch':
      return 'BRUNCH';
    case 'lunch':
      return 'LUNCH';
    case 'dinner':
      return 'DINNER';
    case 'supper':
      return 'SUPPER';
    case 'snack':
      return 'SNACK';
    default:
      return plannerSlotDisplayLabel(daySlotsSorted, slot).toUpperCase();
  }
}

bool _isDiningOut(MealPlanSlot slot) {
  final t = slot.mealText?.trim().toLowerCase() ?? '';
  return t.contains('dining out');
}

/// Stacked day card for the home 3-day outlook (reference UI).
class HomeOutlookDayCard extends StatelessWidget {
  const HomeOutlookDayCard({
    super.key,
    required this.date,
    required this.outlookIndex,
    required this.daySlots,
    required this.recipes,
    required this.onTap,
  });

  final DateTime date;
  /// 0 = TODAY, 1 = TOMORROW, 2 = UPCOMING
  final int outlookIndex;
  final List<MealPlanSlot> daySlots;
  final List<Recipe> recipes;
  final VoidCallback onTap;

  static const BorderRadius cardRadius = BorderRadius.all(Radius.circular(16));

  static const Color _lightTodayFill = Color(0xFFE8E8F5);
  static const Color _lightOtherFill = Color(0xFFFFFFFF);
  static const Color _lightMuted = Color(0xFF8F9BB3);
  static const Color _lightNavy = Color(0xFF2E3A59);
  static const Color _lightBody = Color(0xFF2E3A59);
  static const Color _diningPillBg = Color(0xFFE8F5E9);
  static const Color _diningPillFg = Color(0xFF2E5C3A);

  String get _ribbonLabel {
    switch (outlookIndex) {
      case 0:
        return 'TODAY';
      case 1:
        return 'TOMORROW';
      default:
        return 'UPCOMING';
    }
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final isToday = outlookIndex == 0;

    final fill = isDark
        ? (isToday
            ? scheme.primaryContainer.withValues(alpha: 0.35)
            : scheme.surface)
        : (isToday ? _lightTodayFill : _lightOtherFill);
    final borderColor = isDark
        ? scheme.outlineVariant.withValues(alpha: 0.5)
        : const Color(0xFFE8EAEF);
    final ribbonColor = isDark ? scheme.onSurfaceVariant : _lightMuted;
    final titleColor = isDark ? scheme.onSurface : _lightNavy;
    final dayNumColor =
        isDark ? scheme.onSurfaceVariant.withValues(alpha: 0.45) : _lightMuted;
    final bodyColor = isDark ? scheme.onSurface.withValues(alpha: 0.92) : _lightBody;

    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: cardRadius,
        child: Ink(
          width: double.infinity,
          decoration: BoxDecoration(
            color: fill,
            borderRadius: cardRadius,
            border: Border.all(color: borderColor),
            boxShadow: [
              BoxShadow(
                color: scheme.shadow.withValues(alpha: isDark ? 0.12 : 0.06),
                blurRadius: 10,
                offset: const Offset(0, 3),
              ),
            ],
          ),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
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
                            _ribbonLabel,
                            style: Theme.of(context).textTheme.labelSmall?.copyWith(
                                  letterSpacing: 0.9,
                                  fontWeight: FontWeight.w600,
                                  color: ribbonColor,
                                ),
                          ),
                          const SizedBox(height: 4),
                          Text(
                            DateFormat('EEEE').format(date),
                            style: Theme.of(context).textTheme.titleMedium?.copyWith(
                                  fontWeight: FontWeight.w800,
                                  color: titleColor,
                                ),
                          ),
                        ],
                      ),
                    ),
                    Text(
                      '${date.day}',
                      style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                            fontWeight: FontWeight.w300,
                            color: dayNumColor,
                            height: 1.0,
                          ),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                if (daySlots.isEmpty)
                  Text(
                    'Nothing planned',
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                          color: ribbonColor,
                          fontStyle: FontStyle.italic,
                        ),
                  )
                else
                  ...daySlots.map((slot) {
                    return Padding(
                      padding: const EdgeInsets.only(bottom: 10),
                      child: _slotBlock(
                        context,
                        slot: slot,
                        ribbonColor: ribbonColor,
                        bodyColor: bodyColor,
                      ),
                    );
                  }),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _slotBlock(
    BuildContext context, {
    required MealPlanSlot slot,
    required Color ribbonColor,
    required Color bodyColor,
  }) {
    if (_isDiningOut(slot)) {
      return Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
        decoration: BoxDecoration(
          color: Theme.of(context).brightness == Brightness.dark
              ? Theme.of(context).colorScheme.primaryContainer.withValues(alpha: 0.45)
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
            Text(
              'DINING OUT',
              style: Theme.of(context).textTheme.labelSmall?.copyWith(
                    fontWeight: FontWeight.w800,
                    letterSpacing: 0.6,
                    color: Theme.of(context).brightness == Brightness.dark
                        ? Theme.of(context).colorScheme.onPrimaryContainer
                        : _diningPillFg,
                  ),
            ),
          ],
        ),
      );
    }

    final upper = homeOutlookSlotUpperLabel(slot, daySlots);
    if (!slot.hasPlannedContent) {
      return Text(
        'NO $upper PLANNED',
        style: Theme.of(context).textTheme.labelSmall?.copyWith(
              color: ribbonColor,
              fontStyle: FontStyle.italic,
              fontWeight: FontWeight.w600,
              letterSpacing: 0.35,
            ),
      );
    }

    final line = plannerSlotPrimarySummaryLine(slot, recipes);
    final showDinnerIcon = slot.mealLabel.toLowerCase().trim() == 'dinner' ||
        slot.mealLabel.toLowerCase().trim() == 'supper';

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          upper,
          style: Theme.of(context).textTheme.labelSmall?.copyWith(
                letterSpacing: 0.65,
                fontWeight: FontWeight.w700,
                color: ribbonColor,
              ),
        ),
        const SizedBox(height: 2),
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              child: Text(
                line,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      fontWeight: FontWeight.w600,
                      color: bodyColor,
                      height: 1.25,
                    ),
              ),
            ),
            if (showDinnerIcon) ...[
              const SizedBox(width: 6),
              const Icon(
                Icons.restaurant_rounded,
                size: 18,
                color: Color(0xFFE67E22),
              ),
            ],
          ],
        ),
      ],
    );
  }
}
