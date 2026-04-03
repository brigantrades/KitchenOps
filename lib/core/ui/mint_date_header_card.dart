import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:plateplan/core/theme/app_brand.dart';
import 'package:plateplan/core/theme/design_tokens.dart';

/// Mint gradient date header used on Home day outlook and Planner day sheets.
class MintDateHeaderCard extends StatelessWidget {
  const MintDateHeaderCard({
    super.key,
    required this.date,
    this.icon = Icons.restaurant_menu_rounded,
  });

  final DateTime date;
  final IconData icon;

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final titleColor = isDark ? AppBrand.offWhite : AppBrand.deepTeal;
    final subtitleColor = isDark
        ? AppBrand.offWhite.withValues(alpha: 0.88)
        : AppBrand.deepTeal.withValues(alpha: 0.72);
    final iconBadgeColor = isDark
        ? AppBrand.offWhite.withValues(alpha: 0.18)
        : AppBrand.deepTeal.withValues(alpha: 0.10);

    final scheme = Theme.of(context).colorScheme;

    return Container(
      decoration: BoxDecoration(
        gradient: isDark
            ? AppBrand.headerGradientDark
            : const LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: [AppBrand.paleMint, AppBrand.mutedAqua],
              ),
        borderRadius: BorderRadius.circular(20),
        border: isDark
            ? null
            : Border.all(
                color: AppBrand.mutedAqua.withValues(alpha: 0.85),
                width: 1,
              ),
        boxShadow: isDark
            ? AppShadows.soft
            : [
                BoxShadow(
                  color: scheme.shadow.withValues(alpha: 0.14),
                  blurRadius: 14,
                  spreadRadius: 0,
                  offset: const Offset(0, 5),
                ),
                BoxShadow(
                  color: AppBrand.deepTeal.withValues(alpha: 0.08),
                  blurRadius: 20,
                  spreadRadius: -2,
                  offset: const Offset(0, 8),
                ),
              ],
      ),
      padding: const EdgeInsets.fromLTRB(18, 16, 18, 16),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              color: iconBadgeColor,
              borderRadius: BorderRadius.circular(14),
            ),
            child: Icon(
              icon,
              color: isDark
                  ? AppBrand.offWhite.withValues(alpha: 0.95)
                  : AppBrand.deepTeal,
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
                        color: subtitleColor,
                        fontWeight: FontWeight.w700,
                        letterSpacing: 1.1,
                      ),
                ),
                const SizedBox(height: 4),
                Text(
                  DateFormat('MMM d, yyyy').format(date),
                  style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                        color: titleColor,
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
