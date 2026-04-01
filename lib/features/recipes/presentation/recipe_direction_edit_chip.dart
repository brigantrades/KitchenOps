import 'package:flutter/material.dart';
import 'package:plateplan/core/theme/design_tokens.dart';

/// Pill chip for editing recipe direction steps (cooking mode; wizard blue).
class RecipeDirectionEditChip extends StatelessWidget {
  const RecipeDirectionEditChip({
    super.key,
    required this.label,
    required this.onTap,
    required this.onDelete,
  });

  final String label;
  final VoidCallback onTap;
  final VoidCallback onDelete;

  static const Color _blueLight = Color(0xFFD7EEFF);
  static const Color _blueMid = Color(0xFFB4DEFF);

  /// One-based step number + instruction preview (matches step list UX).
  static String labelForStep(int oneBasedStep, String text) {
    final t = text.trim();
    if (t.isEmpty) {
      return 'Step $oneBasedStep · Tap to edit';
    }
    return '$oneBasedStep. $t';
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;
    return Padding(
      padding: const EdgeInsets.only(bottom: AppSpacing.xs),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          borderRadius: BorderRadius.circular(999),
          onTap: onTap,
          child: Ink(
            decoration: BoxDecoration(
              color: _blueLight,
              borderRadius: BorderRadius.circular(999),
              border: Border.all(color: _blueMid),
            ),
            child: Padding(
              padding:
                  const EdgeInsets.only(left: 10, right: 4, top: 8, bottom: 8),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Icon(
                    Icons.format_list_numbered_rounded,
                    size: 20,
                    color: scheme.primary,
                  ),
                  const SizedBox(width: AppSpacing.xs),
                  Expanded(
                    child: Text(
                      label,
                      maxLines: 4,
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
