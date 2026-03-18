import 'package:flutter/material.dart';
import 'package:plateplan/core/theme/design_tokens.dart';
import 'package:plateplan/core/theme/theme_extensions.dart';

class AppSurface extends StatelessWidget {
  const AppSurface({
    super.key,
    required this.child,
    this.padding = const EdgeInsets.fromLTRB(16, 10, 16, 20),
  });

  final Widget child;
  final EdgeInsets padding;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).extension<AppThemeColors>() ?? AppThemeColors.light;
    return DecoratedBox(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [colors.surfaceBase, colors.surfaceAlt, colors.surfaceBase],
        ),
      ),
      child: ListView(
        padding: padding,
        children: [child],
      ),
    );
  }
}

class AppSection extends StatelessWidget {
  const AppSection({
    super.key,
    required this.child,
    this.bottom = AppSpacing.md,
  });

  final Widget child;
  final double bottom;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.only(bottom: bottom),
      child: child,
    );
  }
}
