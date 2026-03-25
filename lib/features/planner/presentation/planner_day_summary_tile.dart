import 'package:collection/collection.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:plateplan/core/models/app_models.dart';
import 'package:plateplan/core/planner_slot_labels.dart';
import 'package:plateplan/core/theme/theme_extensions.dart';

String plannerSlotPrimarySummaryLine(MealPlanSlot slot, List<Recipe> recipes) {
  final t = slot.mealText?.trim();
  if (t != null && t.isNotEmpty) return t;
  if (slot.recipeId != null) {
    return recipes.firstWhereOrNull((r) => r.id == slot.recipeId)?.title ?? '—';
  }
  return '—';
}

String plannerCondensedMealSummaryLine(
  MealPlanSlot slot,
  List<MealPlanSlot> daySlotsSorted,
  List<Recipe> recipes,
) {
  final tag =
      plannerSlotShortLabel(plannerSlotDisplayLabel(daySlotsSorted, slot));
  final line = plannerSlotPrimarySummaryLine(slot, recipes);
  return '$tag: $line';
}

/// Compact day cell matching the planner grid calendar view.
class PlannerDaySummaryTile extends StatelessWidget {
  const PlannerDaySummaryTile({
    super.key,
    required this.date,
    required this.isToday,
    required this.daySlots,
    required this.recipes,
    required this.scheme,
    required this.appColors,
    this.maxLines = 5,
    this.mealLineMaxLines = 1,
    this.fillParent = true,
    required this.borderRadius,
    required this.onTap,
  });

  static final BorderRadius defaultBorderRadius = BorderRadius.circular(12);

  final DateTime date;
  final bool isToday;
  final List<MealPlanSlot> daySlots;
  final List<Recipe> recipes;
  final ColorScheme scheme;
  final AppThemeColors appColors;
  /// Max slot rows before "+N more"; null shows every slot.
  final int? maxLines;
  /// Max lines per meal; null = wrap fully (no ellipsis).
  final int? mealLineMaxLines;
  /// When true, expand to parent [SizedBox] (planner grid). When false, height follows content.
  final bool fillParent;
  final BorderRadius borderRadius;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final titleColor =
        isToday ? appColors.highlight : scheme.onSurface.withValues(alpha: 0.92);
    final bodyColor = scheme.onSurface.withValues(alpha: 0.88);
    final mutedColor = scheme.onSurfaceVariant.withValues(alpha: 0.9);
    final bodyStyle = Theme.of(context).textTheme.labelSmall?.copyWith(
          height: 1.28,
          fontSize:
              (Theme.of(context).textTheme.labelSmall?.fontSize ?? 11) - 0.5,
          color: bodyColor,
          fontWeight: FontWeight.w500,
        );
    final visible = maxLines == null
        ? daySlots
        : daySlots.take(maxLines!).toList();
    final extra =
        maxLines == null ? 0 : daySlots.length - visible.length;
    final fill = isToday ? appColors.highlightSoft : appColors.panel;
    final borderColor = isToday
        ? appColors.highlight.withValues(alpha: 0.5)
        : appColors.pillBorder.withValues(alpha: 0.85);
    final borderWidth = isToday ? 1.5 : 1.0;

    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: borderRadius,
        splashColor: appColors.highlightSoft.withValues(alpha: 0.35),
        highlightColor: appColors.highlightSoft.withValues(alpha: 0.2),
        child: Ink(
          width: double.infinity,
          height: fillParent ? double.infinity : null,
          decoration: BoxDecoration(
            color: fill,
            borderRadius: borderRadius,
            border: Border.all(color: borderColor, width: borderWidth),
            boxShadow: [
              BoxShadow(
                color: scheme.shadow.withValues(alpha: 0.05),
                blurRadius: 6,
                offset: const Offset(0, 2),
              ),
            ],
          ),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(8, 8, 8, 6),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: fillParent ? MainAxisSize.max : MainAxisSize.min,
              children: [
                Text(
                  DateFormat('EEE d').format(date),
                  style: Theme.of(context).textTheme.labelMedium?.copyWith(
                        fontWeight: FontWeight.w800,
                        letterSpacing: 0.15,
                        color: titleColor,
                      ),
                ),
                const SizedBox(height: 6),
                if (fillParent)
                  Expanded(
                    child: _mealBody(
                      context,
                      daySlots: daySlots,
                      visible: visible,
                      extra: extra,
                      bodyStyle: bodyStyle,
                      mutedColor: mutedColor,
                      scrollable: true,
                    ),
                  )
                else
                  _mealBody(
                    context,
                    daySlots: daySlots,
                    visible: visible,
                    extra: extra,
                    bodyStyle: bodyStyle,
                    mutedColor: mutedColor,
                    scrollable: false,
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _mealBody(
    BuildContext context, {
    required List<MealPlanSlot> daySlots,
    required List<MealPlanSlot> visible,
    required int extra,
    required TextStyle? bodyStyle,
    required Color mutedColor,
    required bool scrollable,
  }) {
    if (daySlots.isEmpty) {
      return Align(
        alignment: Alignment.topLeft,
        child: Text(
          '—',
          style: bodyStyle?.copyWith(color: mutedColor),
        ),
      );
    }

    final column = Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        for (final slot in visible)
          Padding(
            padding: const EdgeInsets.only(bottom: 3),
            child: Text(
              plannerCondensedMealSummaryLine(slot, daySlots, recipes),
              style: bodyStyle,
              maxLines: mealLineMaxLines,
              overflow: mealLineMaxLines != null
                  ? TextOverflow.ellipsis
                  : null,
            ),
          ),
        if (extra > 0)
          Text(
            '+$extra more',
            style: bodyStyle?.copyWith(
              color: mutedColor,
              fontStyle: FontStyle.italic,
              fontWeight: FontWeight.w600,
            ),
          ),
      ],
    );

    if (scrollable) {
      return SingleChildScrollView(
        physics: const BouncingScrollPhysics(),
        child: column,
      );
    }
    return column;
  }
}
