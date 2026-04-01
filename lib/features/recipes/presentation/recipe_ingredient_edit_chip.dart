import 'package:flutter/material.dart';
import 'package:plateplan/core/models/app_models.dart';
import 'package:plateplan/core/measurement/ingredient_display_units.dart';
import 'package:plateplan/core/measurement/measurement_system.dart';
import 'package:plateplan/core/strings/ingredient_amount_display.dart';
import 'package:plateplan/core/theme/design_tokens.dart';

/// Visual style for tappable ingredient pills (create wizard vs import preview).
enum RecipeIngredientChipStyle {
  createWizardBlue,
  importPink,
}

/// Pill chip for editing recipe ingredients (tap body to edit, X to remove).
class RecipeIngredientEditChip extends StatelessWidget {
  const RecipeIngredientEditChip({
    super.key,
    required this.label,
    required this.onTap,
    required this.onDelete,
    this.style = RecipeIngredientChipStyle.createWizardBlue,
  });

  final String label;
  final VoidCallback onTap;
  final VoidCallback onDelete;
  final RecipeIngredientChipStyle style;

  /// Same line as cooking-mode checkbox and import preview chip (no measurement conversion).
  static String labelForIngredient(Ingredient ingredient) {
    final name =
        ingredient.name.trim().isEmpty ? 'Ingredient' : ingredient.name.trim();
    if (ingredient.qualitative) {
      final q = ingredient.unit.trim();
      return q.isEmpty ? name : '$name · $q';
    }
    final amount =
        ingredient.amount > 0 ? formatIngredientAmount(ingredient.amount) : '';
    final unit = ingredient.unit.trim();
    if (amount.isEmpty) return unit.isEmpty ? name : '$name · $unit';
    return unit.isEmpty ? '$name · $amount' : '$name · $amount $unit';
  }

  /// Cooking-mode style line using the user’s measurement system.
  static String labelForIngredientWithSystem(
    Ingredient ingredient,
    MeasurementSystem system,
  ) {
    if (ingredient.qualitative) {
      final q = ingredient.unit.trim();
      final name =
          ingredient.name.trim().isEmpty ? 'Ingredient' : ingredient.name.trim();
      return q.isEmpty ? name : '$name · $q';
    }
    return '${ingredientDisplayQuantityLabel(ingredient, system)} ${ingredient.name}';
  }

  static const Color _blueLight = Color(0xFFD7EEFF);
  static const Color _blueMid = Color(0xFFB4DEFF);
  static const Color _pinkLight = Color(0xFFFFE8EE);
  static const Color _pinkMid = Color(0xFFE8A8B8);

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;
    final (Color fill, Color border) = switch (style) {
      RecipeIngredientChipStyle.createWizardBlue => (_blueLight, _blueMid),
      RecipeIngredientChipStyle.importPink => (_pinkLight, _pinkMid),
    };
    return Padding(
      padding: const EdgeInsets.only(bottom: AppSpacing.xs),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          borderRadius: BorderRadius.circular(999),
          onTap: onTap,
          child: Ink(
            decoration: BoxDecoration(
              color: fill,
              borderRadius: BorderRadius.circular(999),
              border: Border.all(color: border),
            ),
            child: Padding(
              padding:
                  const EdgeInsets.only(left: 10, right: 4, top: 8, bottom: 8),
              child: Row(
                children: [
                  Icon(
                    Icons.restaurant_rounded,
                    size: 20,
                    color: scheme.primary,
                  ),
                  const SizedBox(width: AppSpacing.xs),
                  Expanded(
                    child: Text(
                      label,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: textTheme.bodyMedium?.copyWith(
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                  Icon(
                    Icons.edit_outlined,
                    size: 18,
                    color: scheme.onSurfaceVariant,
                  ),
                  IconButton(
                    onPressed: onDelete,
                    icon: const Icon(Icons.close_rounded, size: 20),
                    tooltip: 'Remove',
                    visualDensity: VisualDensity.compact,
                    padding: EdgeInsets.zero,
                    constraints: const BoxConstraints(
                      minWidth: 36,
                      minHeight: 36,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
