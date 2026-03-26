import 'package:flutter/material.dart';
import 'package:plateplan/core/models/app_models.dart';
import 'package:plateplan/core/theme/design_tokens.dart';
import 'package:plateplan/core/theme/theme_extensions.dart';

class EditorialHero extends StatelessWidget {
  const EditorialHero({
    super.key,
    required this.title,
    required this.subtitle,
    required this.primaryLabel,
    required this.onPrimaryTap,
    this.secondary,
    this.imageUrl,
  });

  final String title;
  final String subtitle;
  final String primaryLabel;
  final VoidCallback onPrimaryTap;
  final Widget? secondary;
  final String? imageUrl;

  @override
  Widget build(BuildContext context) {
    final colors =
        Theme.of(context).extension<AppThemeColors>() ?? AppThemeColors.light;
    return Container(
      padding: const EdgeInsets.all(AppSpacing.lg),
      decoration: BoxDecoration(
        borderRadius: AppRadius.hero,
        boxShadow: AppShadows.floating,
        image: imageUrl == null
            ? null
            : DecorationImage(
                image: NetworkImage(imageUrl!),
                fit: BoxFit.cover,
              ),
        gradient: imageUrl == null
            ? LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: [colors.heroStart, colors.heroEnd, colors.heroAccent],
              )
            : null,
      ),
      child: Container(
        decoration: BoxDecoration(
          borderRadius: AppRadius.md,
          gradient: LinearGradient(
            begin: Alignment.bottomCenter,
            end: Alignment.topCenter,
            colors: [Colors.black.withValues(alpha: 0.58), Colors.transparent],
          ),
        ),
        padding: const EdgeInsets.all(AppSpacing.md),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              title,
              style: Theme.of(context).textTheme.displaySmall?.copyWith(
                    color: Colors.white,
                    fontWeight: FontWeight.w700,
                  ),
            ),
            const SizedBox(height: AppSpacing.xs),
            Text(
              subtitle,
              style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                    color: Colors.white.withValues(alpha: 0.92),
                  ),
            ),
            const SizedBox(height: AppSpacing.md),
            Row(
              children: [
                FilledButton(
                  onPressed: onPrimaryTap,
                  style: FilledButton.styleFrom(
                    backgroundColor: Theme.of(context).colorScheme.primary,
                    foregroundColor: Theme.of(context).colorScheme.onPrimary,
                  ),
                  child: Text(primaryLabel),
                ),
                if (secondary != null) ...[
                  const SizedBox(width: AppSpacing.sm),
                  Expanded(child: secondary!),
                ],
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class SegmentedPills extends StatelessWidget {
  const SegmentedPills({
    super.key,
    required this.labels,
    required this.selectedIndex,
    required this.onSelect,
  });

  final List<String> labels;
  final int selectedIndex;
  final ValueChanged<int> onSelect;

  @override
  Widget build(BuildContext context) {
    final colors =
        Theme.of(context).extension<AppThemeColors>() ?? AppThemeColors.light;
    return Container(
      padding: const EdgeInsets.all(AppSpacing.xs),
      decoration: BoxDecoration(
        color: colors.panelStrong,
        borderRadius: AppRadius.sm,
      ),
      child: Row(
        children: List.generate(
          labels.length,
          (i) => Expanded(
            child: GestureDetector(
              onTap: () => onSelect(i),
              child: AnimatedContainer(
                duration: AppMotion.fast,
                padding: const EdgeInsets.symmetric(vertical: 10),
                decoration: BoxDecoration(
                  borderRadius: AppRadius.sm,
                  color: i == selectedIndex
                      ? Theme.of(context).colorScheme.secondary
                      : Colors.transparent,
                ),
                child: Text(
                  labels[i],
                  textAlign: TextAlign.center,
                  style: Theme.of(context).textTheme.labelLarge?.copyWith(
                        color: i == selectedIndex
                            ? Theme.of(context).colorScheme.onSecondary
                            : Theme.of(context).colorScheme.onSurfaceVariant,
                        fontWeight: FontWeight.w700,
                      ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class RecipeListCard extends StatelessWidget {
  const RecipeListCard({
    super.key,
    required this.title,
    required this.meta,
    required this.onTap,
    this.tags = const <String>[],
    this.trailing,
  });

  final String title;
  final String meta;
  final VoidCallback onTap;
  final List<String> tags;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    final colors =
        Theme.of(context).extension<AppThemeColors>() ?? AppThemeColors.light;
    return InkWell(
      borderRadius: AppRadius.md,
      onTap: onTap,
      child: Container(
        decoration: BoxDecoration(
          borderRadius: AppRadius.md,
          color: colors.panel,
          boxShadow: AppShadows.soft,
        ),
        clipBehavior: Clip.antiAlias,
        child: Padding(
          padding: const EdgeInsets.all(AppSpacing.md),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: Theme.of(context).textTheme.titleMedium?.copyWith(
                            fontWeight: FontWeight.w700,
                          ),
                    ),
                    const SizedBox(height: AppSpacing.xs),
                    Text(meta, style: Theme.of(context).textTheme.bodySmall),
                    if (tags.isNotEmpty) ...[
                      const SizedBox(height: AppSpacing.sm),
                      Wrap(
                        spacing: 6,
                        runSpacing: 6,
                        children: tags.take(3).map((tag) {
                          return Chip(
                            label: Text(tag),
                            visualDensity: VisualDensity.compact,
                            materialTapTargetSize:
                                MaterialTapTargetSize.shrinkWrap,
                          );
                        }).toList(),
                      ),
                    ],
                  ],
                ),
              ),
              if (trailing != null) trailing!,
            ],
          ),
        ),
      ),
    );
  }
}

class BrandedSheetScaffold extends StatelessWidget {
  const BrandedSheetScaffold({
    super.key,
    required this.title,
    required this.child,
    this.trailing,
  });

  final String title;
  final Widget child;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    title,
                    style: Theme.of(context).textTheme.titleLarge?.copyWith(
                          fontWeight: FontWeight.w700,
                        ),
                  ),
                ),
                if (trailing != null) trailing!,
              ],
            ),
            const SizedBox(height: AppSpacing.sm),
            child,
          ],
        ),
      ),
    );
  }
}

class DiscoverRecipeShowcaseCard extends StatelessWidget {
  const DiscoverRecipeShowcaseCard({
    super.key,
    required this.recipe,
    required this.onTap,
    this.trailing,
    this.badgeLabel,
    this.imageFit = BoxFit.contain,
  });

  final Recipe recipe;
  final VoidCallback onTap;
  final Widget? trailing;
  final String? badgeLabel;
  final BoxFit imageFit;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final totalTime = (recipe.prepTime ?? 0) + (recipe.cookTime ?? 0);
    return InkWell(
      onTap: onTap,
      borderRadius: AppRadius.md,
      child: Container(
        decoration: const BoxDecoration(
          color: Colors.white,
          borderRadius: AppRadius.md,
          boxShadow: AppShadows.soft,
        ),
        clipBehavior: Clip.antiAlias,
        child: Row(
          children: [
            ClipRRect(
              borderRadius: const BorderRadius.horizontal(
                left: Radius.circular(24),
              ),
              child: Container(
                color: const Color(0xFFE8E1D4),
                child: FoodMedia(
                  imageUrl: recipe.imageUrl,
                  width: 112,
                  height: 112,
                  fit: imageFit,
                ),
              ),
            ),
            Expanded(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    if (badgeLabel != null)
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 8,
                          vertical: 4,
                        ),
                        decoration: const BoxDecoration(
                          color: Color(0xFFF9B77D),
                          borderRadius: AppRadius.pill,
                        ),
                        child: Text(
                          badgeLabel!,
                          style:
                              Theme.of(context).textTheme.labelSmall?.copyWith(
                                    fontWeight: FontWeight.w700,
                                    color: const Color(0xFF4A2D0C),
                                  ),
                        ),
                      ),
                    if (badgeLabel != null) const SizedBox(height: 6),
                    Text(
                      recipe.title,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: Theme.of(context).textTheme.titleMedium?.copyWith(
                            fontWeight: FontWeight.w700,
                          ),
                    ),
                    const SizedBox(height: 6),
                    Text(
                      totalTime > 0 ? '$totalTime min' : 'Quick recipe',
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(
                            color: scheme.onSurfaceVariant,
                          ),
                    ),
                    const SizedBox(height: 6),
                    Row(
                      children: [
                        const Icon(Icons.star_rounded,
                            size: 16, color: Color(0xFFF2C94C)),
                        const SizedBox(width: 2),
                        Text(
                          _displayRating(recipe),
                          style:
                              Theme.of(context).textTheme.labelSmall?.copyWith(
                                    fontWeight: FontWeight.w700,
                                  ),
                        ),
                        const Spacer(),
                        if (trailing != null) trailing!,
                      ],
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class DiscoverCuisineCard extends StatelessWidget {
  const DiscoverCuisineCard({
    super.key,
    required this.title,
    required this.subtitle,
    required this.color,
    required this.icon,
    required this.onTap,
    this.graphicUrl,
  });

  final String title;
  final String subtitle;
  final Color color;
  final IconData icon;
  final VoidCallback onTap;
  final String? graphicUrl;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: AppRadius.sm,
      child: Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: color,
          borderRadius: AppRadius.sm,
          boxShadow: AppShadows.soft,
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            SizedBox(
              height: 56,
              width: 56,
              child: graphicUrl == null
                  ? Icon(icon, color: const Color(0xFF2D3436), size: 36)
                  : ClipRRect(
                      borderRadius: BorderRadius.circular(10),
                      child: Image.network(
                        graphicUrl!,
                        fit: BoxFit.cover,
                        errorBuilder: (_, __, ___) => Icon(
                          icon,
                          color: const Color(0xFF2D3436),
                          size: 36,
                        ),
                      ),
                    ),
            ),
            const Spacer(),
            Text(
              title,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              textAlign: TextAlign.center,
              style: Theme.of(context).textTheme.labelLarge?.copyWith(
                    fontWeight: FontWeight.w700,
                    color: const Color(0xFF2D3436),
                  ),
            ),
            const SizedBox(height: 2),
            Text(
              subtitle,
              textAlign: TextAlign.center,
              style: Theme.of(context).textTheme.labelSmall?.copyWith(
                    color: const Color(0xFF2D3436).withValues(alpha: 0.8),
                  ),
            ),
          ],
        ),
      ),
    );
  }
}

String _displayRating(Recipe recipe) {
  final value = 3.6 + ((recipe.title.length % 10) / 10);
  return value.clamp(3.0, 4.8).toStringAsFixed(1);
}

class FoodMedia extends StatelessWidget {
  const FoodMedia({
    super.key,
    required this.imageUrl,
    this.height,
    this.width,
    this.fit = BoxFit.cover,
    this.alignment = Alignment.center,
  });

  final String? imageUrl;
  final double? height;
  final double? width;
  final BoxFit fit;
  final AlignmentGeometry alignment;

  @override
  Widget build(BuildContext context) {
    if (imageUrl == null || imageUrl!.trim().isEmpty) {
      return _FoodPlaceholder(height: height, width: width);
    }
    return Image.network(
      imageUrl!,
      fit: fit,
      alignment: alignment,
      width: width ?? double.infinity,
      height: height,
      filterQuality: FilterQuality.high,
      errorBuilder: (_, __, ___) =>
          _FoodPlaceholder(height: height, width: width),
    );
  }
}

class _FoodPlaceholder extends StatelessWidget {
  const _FoodPlaceholder({this.height, this.width});

  final double? height;
  final double? width;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final w = width ?? double.infinity;
    final compact = width != null && height != null;
    return Container(
      height: height,
      width: w,
      decoration: BoxDecoration(
        borderRadius: compact ? BorderRadius.circular(12) : AppRadius.hero,
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            scheme.primaryContainer,
            scheme.tertiary.withValues(alpha: 0.75),
          ],
        ),
      ),
      child: Icon(
        Icons.restaurant_menu_rounded,
        size: compact ? 32 : 56,
        color: scheme.onPrimaryContainer.withValues(alpha: 0.55),
      ),
    );
  }
}
