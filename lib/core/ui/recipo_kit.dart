import 'package:flutter/material.dart';
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

class MediaRecipeCard extends StatelessWidget {
  const MediaRecipeCard({
    super.key,
    required this.title,
    required this.meta,
    required this.imageUrl,
    required this.onTap,
    this.heroTag,
    this.tags = const <String>[],
    this.trailing,
  });

  final String title;
  final String meta;
  final String imageUrl;
  final VoidCallback onTap;
  final Object? heroTag;
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
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            AspectRatio(
              aspectRatio: 16 / 10,
              child: heroTag == null
                  ? FoodMedia(imageUrl: imageUrl)
                  : Hero(tag: heroTag!, child: FoodMedia(imageUrl: imageUrl)),
            ),
            Padding(
              padding: const EdgeInsets.all(AppSpacing.md),
              child: Row(
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          title,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style:
                              Theme.of(context).textTheme.titleMedium?.copyWith(
                                    fontWeight: FontWeight.w700,
                                  ),
                        ),
                        const SizedBox(height: AppSpacing.xs),
                        Text(meta,
                            style: Theme.of(context).textTheme.bodySmall),
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
          ],
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

class FoodMedia extends StatelessWidget {
  const FoodMedia({
    super.key,
    required this.imageUrl,
    this.height,
  });

  final String? imageUrl;
  final double? height;

  @override
  Widget build(BuildContext context) {
    if (imageUrl == null || imageUrl!.trim().isEmpty) {
      return _FoodPlaceholder(height: height);
    }
    return Image.network(
      imageUrl!,
      fit: BoxFit.cover,
      width: double.infinity,
      height: height,
      errorBuilder: (_, __, ___) => _FoodPlaceholder(height: height),
    );
  }
}

class _FoodPlaceholder extends StatelessWidget {
  const _FoodPlaceholder({this.height});

  final double? height;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      height: height,
      width: double.infinity,
      decoration: BoxDecoration(
        borderRadius: AppRadius.hero,
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
        size: 56,
        color: scheme.onPrimaryContainer.withValues(alpha: 0.55),
      ),
    );
  }
}
