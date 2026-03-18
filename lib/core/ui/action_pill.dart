import 'package:flutter/material.dart';
import 'package:plateplan/core/theme/design_tokens.dart';
import 'package:plateplan/core/theme/theme_extensions.dart';

class ActionPill extends StatelessWidget {
  const ActionPill({
    super.key,
    required this.label,
    required this.onTap,
    this.icon,
    this.selected = false,
  });

  final String label;
  final VoidCallback onTap;
  final IconData? icon;
  final bool selected;

  @override
  Widget build(BuildContext context) {
    final colors =
        Theme.of(context).extension<AppThemeColors>() ?? AppThemeColors.light;
    final scheme = Theme.of(context).colorScheme;
    return InkWell(
      onTap: onTap,
      borderRadius: AppRadius.sm,
      child: AnimatedContainer(
        duration: AppMotion.fast,
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
        decoration: BoxDecoration(
          borderRadius: AppRadius.sm,
          color: selected ? scheme.secondary : colors.pillBg,
          border: Border.all(
              color: selected ? scheme.secondary : colors.pillBorder),
          boxShadow: selected ? AppShadows.soft : const [],
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (icon != null) ...[
              Icon(
                icon,
                size: 16,
                color: selected ? scheme.onSecondary : scheme.onSurfaceVariant,
              ),
              const SizedBox(width: 6),
            ],
            Text(
              label,
              style: Theme.of(context).textTheme.labelLarge?.copyWith(
                    color:
                        selected ? scheme.onSecondary : scheme.onSurfaceVariant,
                  ),
            ),
          ],
        ),
      ),
    );
  }
}
