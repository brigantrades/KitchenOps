import 'package:flutter/material.dart';
import 'package:plateplan/core/theme/design_tokens.dart';
import 'package:plateplan/core/theme/theme_extensions.dart';

class HeroPanel extends StatelessWidget {
  const HeroPanel({
    super.key,
    required this.child,
    this.padding = const EdgeInsets.all(16),
  });

  final Widget child;
  final EdgeInsets padding;

  @override
  Widget build(BuildContext context) {
    final colors =
        Theme.of(context).extension<AppThemeColors>() ?? AppThemeColors.light;
    return Container(
      decoration: BoxDecoration(
        borderRadius: AppRadius.hero,
        gradient: LinearGradient(
          colors: [colors.heroStart, colors.heroEnd, colors.heroAccent],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        boxShadow: AppShadows.floating,
      ),
      child: Padding(
        padding: padding,
        child: child,
      ),
    );
  }
}
