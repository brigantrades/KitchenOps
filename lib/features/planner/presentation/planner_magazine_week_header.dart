import 'package:flutter/material.dart';

/// Centered week title with flanking circular navigation (planner magazine layout).
class PlannerMagazineWeekHeader extends StatelessWidget {
  const PlannerMagazineWeekHeader({
    super.key,
    required this.rangeTitle,
    required this.subtitle,
    required this.onPrevious,
    required this.onNext,
  });

  final String rangeTitle;
  final String subtitle;
  final VoidCallback onPrevious;
  final VoidCallback onNext;

  static const Color _lightTitle = Color(0xFF2E3A59);
  static const Color _lightSubtitle = Color(0xFF7A8499);

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final titleColor = isDark ? scheme.onSurface : _lightTitle;
    final subtitleColor = isDark ? scheme.onSurfaceVariant : _lightSubtitle;
    final navBg = isDark ? scheme.surfaceContainerHighest : Colors.white;
    final navFg = isDark ? scheme.onSurface : _lightTitle;

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 4),
      child: Row(
        children: [
          _RoundNavButton(
            icon: Icons.chevron_left_rounded,
            tooltip: 'Previous',
            onPressed: onPrevious,
            background: navBg,
            foreground: navFg,
          ),
          Expanded(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  rangeTitle,
                  textAlign: TextAlign.center,
                  style: Theme.of(context).textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.w800,
                        letterSpacing: 0.6,
                        color: titleColor,
                        height: 1.2,
                      ),
                ),
                const SizedBox(height: 4),
                Text(
                  subtitle,
                  textAlign: TextAlign.center,
                  style: Theme.of(context).textTheme.labelSmall?.copyWith(
                        letterSpacing: 1.2,
                        fontWeight: FontWeight.w600,
                        color: subtitleColor,
                      ),
                ),
              ],
            ),
          ),
          _RoundNavButton(
            icon: Icons.chevron_right_rounded,
            tooltip: 'Next',
            onPressed: onNext,
            background: navBg,
            foreground: navFg,
          ),
        ],
      ),
    );
  }
}

class _RoundNavButton extends StatelessWidget {
  const _RoundNavButton({
    required this.icon,
    required this.tooltip,
    required this.onPressed,
    required this.background,
    required this.foreground,
  });

  final IconData icon;
  final String tooltip;
  final VoidCallback onPressed;
  final Color background;
  final Color foreground;

  @override
  Widget build(BuildContext context) {
    return IconButton(
      tooltip: tooltip,
      padding: EdgeInsets.zero,
      constraints: const BoxConstraints(minWidth: 44, minHeight: 44),
      style: IconButton.styleFrom(
        foregroundColor: foreground,
        backgroundColor: background,
        shape: const CircleBorder(),
      ),
      onPressed: onPressed,
      icon: Icon(icon),
    );
  }
}
