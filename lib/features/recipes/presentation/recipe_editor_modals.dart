import 'package:flutter/foundation.dart' show listEquals;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:plateplan/core/models/app_models.dart';
import 'package:plateplan/core/theme/design_tokens.dart';
import 'package:plateplan/core/ui/food_icon_resolver.dart';
import 'package:plateplan/core/ui/measurement_system_toggle.dart';
import 'package:plateplan/core/measurement/ingredient_display_units.dart';
import 'package:plateplan/core/measurement/ingredient_unit_profile.dart';
import 'package:plateplan/core/measurement/measurement_system.dart';
import 'package:plateplan/core/measurement/measurement_system_provider.dart';
import 'package:plateplan/core/strings/ingredient_amount_display.dart';
import 'package:plateplan/features/grocery/data/grocery_repository.dart';
import 'package:plateplan/features/grocery/presentation/grocery_item_suggestions_grid.dart';

// --- Constants (aligned with create-recipe wizard) ---

const double kRecipeIngredientAmountEpsilon = 1e-9;

class RecipePresetAmountChip {
  const RecipePresetAmountChip({required this.label, required this.canonicalText});
  final String label;
  final String canonicalText;
}

const kRecipePresetAmountChips = [
  RecipePresetAmountChip(label: '¼', canonicalText: '1/4'),
  RecipePresetAmountChip(label: '⅓', canonicalText: '1/3'),
  RecipePresetAmountChip(label: '½', canonicalText: '1/2'),
  RecipePresetAmountChip(label: '1', canonicalText: '1'),
];

const kRecipeQualitativePresets = [
  'to taste',
  'as needed',
  'pinch',
  '1 tsp',
  '1 tbsp',
  '½ tsp',
];

/// Direction step editor card (matches wizard blues).
const Color kRecipeDirectionStepLight = Color(0xFFD7EEFF);
const Color kRecipeDirectionStepMid = Color(0xFFB4DEFF);

// --- Row state ---

class RecipeIngredientFormRow {
  RecipeIngredientFormRow({
    required String name,
    required List<String> unitOptions,
    required this.selectedUnit,
    String? customUnit,
    String? reorderId,
    bool qualitative = false,
    String qualitativePhrase = '',
  })  : unitOptions = List<String>.from(unitOptions),
        reorderId = reorderId ?? 'ing_${_nextReorderId++}' {
    nameCtrl.text = name;
    if (customUnit != null) {
      customUnitCtrl.text = customUnit;
    }
    this.qualitative = qualitative;
    if (qualitative) {
      final t = qualitativePhrase.trim();
      if (t.isEmpty) {
        qualitativePreset = 'to taste';
      } else if (kRecipeQualitativePresets.contains(t)) {
        qualitativePreset = t;
      } else {
        qualitativePreset = 'custom';
        qualitativeCustomCtrl.text = t;
      }
    }
  }

  static int _nextReorderId = 0;

  final String reorderId;
  final TextEditingController nameCtrl = TextEditingController();
  final TextEditingController amountCtrl = TextEditingController();
  final TextEditingController customUnitCtrl = TextEditingController();
  final TextEditingController qualitativeCustomCtrl = TextEditingController();
  List<String> unitOptions;
  String selectedUnit;

  bool qualitative = false;
  String qualitativePreset = 'to taste';

  final FocusNode nameFocusNode = FocusNode();
  final FocusNode amountFocusNode = FocusNode();
  final FocusNode qualitativeCustomFocusNode = FocusNode();
  final FocusNode customUnitFocusNode = FocusNode();

  bool namePickedFromSuggestions = false;

  String get name => nameCtrl.text.trim();

  String resolvedQualitativePhrase() {
    if (!qualitative) return '';
    if (qualitativePreset == 'custom') {
      return qualitativeCustomCtrl.text.trim();
    }
    return qualitativePreset;
  }

  void dispose() {
    nameFocusNode.dispose();
    amountFocusNode.dispose();
    qualitativeCustomFocusNode.dispose();
    customUnitFocusNode.dispose();
    nameCtrl.dispose();
    amountCtrl.dispose();
    customUnitCtrl.dispose();
    qualitativeCustomCtrl.dispose();
  }
}

/// Hydrates a form row from an [Ingredient] (same rules as recipe wizard).
RecipeIngredientFormRow hydrateRecipeIngredientFormRow(
  Ingredient? initial,
  MeasurementSystem system,
) {
  if (initial == null) {
    final profile = detectUnitProfile('', system);
    return RecipeIngredientFormRow(
      name: '',
      unitOptions: profile.options,
      selectedUnit: profile.defaultUnit,
    );
  }
  if (initial.qualitative) {
    final profile = detectUnitProfile(initial.name, system);
    return RecipeIngredientFormRow(
      name: initial.name,
      unitOptions: profile.options,
      selectedUnit: profile.defaultUnit,
      qualitative: true,
      qualitativePhrase: initial.unit,
    );
  }
  final profile = detectUnitProfile(initial.name, system);
  final normalizedUnit = initial.unit.trim().toLowerCase();
  final isCustom = !profile.options.contains(normalizedUnit);
  final units = [...profile.options];
  final row = RecipeIngredientFormRow(
    name: initial.name,
    unitOptions: units,
    selectedUnit: isCustom ? 'custom' : normalizedUnit,
    customUnit: isCustom ? initial.unit : null,
  );
  row.amountCtrl.text = formatIngredientAmount(initial.amount);
  return row;
}

Ingredient ingredientFromFormRow(
  RecipeIngredientFormRow row, {
  Ingredient? mergeMetadataFrom,
}) {
  final base = mergeMetadataFrom;
  if (row.qualitative) {
    return Ingredient(
      name: row.nameCtrl.text.trim(),
      amount: 0,
      unit: row.resolvedQualitativePhrase(),
      category: base?.category ?? GroceryCategory.other,
      qualitative: true,
      fdcId: base?.fdcId,
      fdcDescription: base?.fdcDescription,
      lineNutrition: base?.lineNutrition,
      fdcNutritionEstimated: base?.fdcNutritionEstimated ?? false,
      fdcTypicalAverage: base?.fdcTypicalAverage ?? false,
    );
  }
  final unit = row.selectedUnit == 'custom'
      ? row.customUnitCtrl.text.trim()
      : row.selectedUnit;
  return Ingredient(
    name: row.nameCtrl.text.trim(),
    amount: parseRecipeIngredientAmount(row.amountCtrl.text) ?? 0,
    unit: unit,
    category: base?.category ?? GroceryCategory.other,
    qualitative: false,
    fdcId: base?.fdcId,
    fdcDescription: base?.fdcDescription,
    lineNutrition: base?.lineNutrition,
    fdcNutritionEstimated: base?.fdcNutritionEstimated ?? false,
    fdcTypicalAverage: base?.fdcTypicalAverage ?? false,
  );
}

class RecipeDirectionDraft {
  RecipeDirectionDraft({String? text}) {
    if (text != null) textCtrl.text = text;
  }

  final TextEditingController textCtrl = TextEditingController();

  void dispose() {
    textCtrl.dispose();
  }
}

// --- Parsing / validation ---

double? parseRecipeIngredientAmount(String raw) {
  final s = raw.trim();
  if (s.isEmpty) return null;
  final direct = double.tryParse(s);
  if (direct != null) return direct;
  final slash = RegExp(r'^\s*(\d+)\s*/\s*(\d+)\s*$').firstMatch(s);
  if (slash != null) {
    final n = int.tryParse(slash.group(1)!);
    final d = int.tryParse(slash.group(2)!);
    if (n != null && d != null && d != 0) return n / d;
  }
  return null;
}

bool isRecipeIngredientRowComplete(RecipeIngredientFormRow row) {
  if (row.nameCtrl.text.trim().isEmpty) return false;
  if (row.qualitative) {
    return row.resolvedQualitativePhrase().isNotEmpty;
  }
  if (row.amountCtrl.text.trim().isEmpty) return false;
  if (parseRecipeIngredientAmount(row.amountCtrl.text) == null) return false;
  if (row.selectedUnit.trim().isEmpty) return false;
  if (row.selectedUnit == 'custom' &&
      row.customUnitCtrl.text.trim().isEmpty) {
    return false;
  }
  return true;
}

bool isRecipePresetAmountSelected(RecipeIngredientFormRow row, String canonical) {
  final a = parseRecipeIngredientAmount(row.amountCtrl.text);
  final b = parseRecipeIngredientAmount(canonical);
  if (a == null || b == null) return false;
  return (a - b).abs() < kRecipeIngredientAmountEpsilon;
}

bool isRecipeDirectionStepComplete(RecipeDirectionDraft draft) {
  return draft.textCtrl.text.trim().isNotEmpty;
}

/// Updates [row] units/amount for [next] after [measurementSystemProvider] was set.
void applyMeasurementSystemToRow(
  RecipeIngredientFormRow row,
  MeasurementSystem next,
) {
  final profile = detectUnitProfile(row.nameCtrl.text, next);
  row.unitOptions
    ..clear()
    ..addAll(profile.options);
  if (row.qualitative) return;
  final amt = parseRecipeIngredientAmount(row.amountCtrl.text);
  final unit = row.selectedUnit == 'custom'
      ? row.customUnitCtrl.text.trim()
      : row.selectedUnit;
  if (amt == null || unit.isEmpty) return;
  final conv = convertAmountAndUnitForMeasurementSystem(
    amount: amt,
    unitRaw: unit,
    target: next,
  );
  if (conv != null) {
    final matched = matchUnitOption(row.unitOptions, conv.unit);
    if (matched != null) {
      row.selectedUnit = matched;
      row.customUnitCtrl.clear();
    } else {
      row.selectedUnit = 'custom';
      row.customUnitCtrl.text = conv.unit;
    }
    row.amountCtrl.text = formatConvertedIngredientAmount(conv.amount, conv.unit);
  } else {
    final matched = matchUnitOption(row.unitOptions, unit);
    if (matched != null) {
      row.selectedUnit = matched;
      row.customUnitCtrl.clear();
    } else {
      row.selectedUnit = 'custom';
      row.customUnitCtrl.text = unit;
    }
  }
}

// --- Theme & decorations ---

ThemeData themeForRecipeEditorModal(BuildContext sheetContext) {
  return Theme.of(sheetContext).copyWith(
    inputDecorationTheme: InputDecorationTheme(
      filled: true,
      fillColor: const Color(0xFFEFF6FF),
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(14),
        borderSide: BorderSide.none,
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(14),
        borderSide: BorderSide.none,
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(14),
        borderSide: BorderSide(
          color: Theme.of(sheetContext).colorScheme.primary,
          width: 1.2,
        ),
      ),
    ),
  );
}

const double _kIngredientFieldBorderRadius = 14;
const double _kDirectionFieldBorderRadius = 14;

InputDecoration recipeIngredientInputDecoration(
  BuildContext context, {
  String? labelText,
  String? hintText,
  TextStyle? hintStyle,
  EdgeInsetsGeometry contentPadding =
      const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
  double borderOpacity = 1.0,
  Widget? prefixIcon,
}) {
  final scheme = Theme.of(context).colorScheme;
  final borderColor = scheme.primary.withValues(alpha: borderOpacity);
  final border = OutlineInputBorder(
    borderRadius: BorderRadius.circular(_kIngredientFieldBorderRadius),
    borderSide: BorderSide(color: borderColor, width: 1.2),
  );
  return InputDecoration(
    filled: true,
    fillColor: Colors.white,
    labelText: labelText,
    hintText: hintText,
    hintStyle: hintStyle,
    isDense: true,
    contentPadding: contentPadding,
    prefixIcon: prefixIcon,
    prefixIconConstraints: prefixIcon == null
        ? null
        : const BoxConstraints(minWidth: 40, minHeight: 32),
    border: border,
    enabledBorder: border,
    focusedBorder: border,
    disabledBorder: border,
  );
}

InputDecoration recipeDirectionInstructionDecoration(BuildContext context) {
  final border = OutlineInputBorder(
    borderRadius: BorderRadius.circular(_kDirectionFieldBorderRadius),
    borderSide: const BorderSide(color: kRecipeDirectionStepMid, width: 1.2),
  );
  return InputDecoration(
    filled: true,
    fillColor: Colors.white,
    labelText: 'Instruction',
    hintText: 'Describe what to do for this step',
    isDense: true,
    contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
    border: border,
    enabledBorder: border,
    focusedBorder: border,
    disabledBorder: border,
  );
}

// --- Icons ---

IconData groceryCategoryIcon(GroceryCategory category) {
  return switch (category) {
    GroceryCategory.produce => Icons.eco_rounded,
    GroceryCategory.meatFish => Icons.set_meal_rounded,
    GroceryCategory.dairyEggs => Icons.egg_alt_rounded,
    GroceryCategory.pantryGrains => Icons.rice_bowl_rounded,
    GroceryCategory.bakery => Icons.bakery_dining_rounded,
    GroceryCategory.other => Icons.shopping_bag_rounded,
  };
}

Widget ingredientPickedFoodIcon(
  BuildContext context,
  WidgetRef ref,
  RecipeIngredientFormRow row, {
  double size = 24,
}) {
  final repo = ref.read(groceryRepositoryProvider);
  final name = row.nameCtrl.text.trim();
  if (name.isEmpty) {
    return SizedBox(width: size, height: size);
  }
  final category = repo.categorize(name);
  final asset = foodIconAssetForName(name, category: category);
  final color = Theme.of(context).colorScheme.onSurfaceVariant;
  if (asset != null) {
    return Image.asset(
      asset,
      width: size,
      height: size,
      filterQuality: FilterQuality.high,
      errorBuilder: (_, __, ___) => Icon(
        groceryCategoryIcon(category),
        size: size,
        color: color,
      ),
    );
  }
  return Icon(
    groceryCategoryIcon(category),
    size: size,
    color: color,
  );
}

// --- Scroll into view ---

class IngredientCardScrollIntoView extends StatefulWidget {
  const IngredientCardScrollIntoView({
    super.key,
    required this.focusNodes,
    required this.cardKey,
    required this.child,
  });

  final List<FocusNode> focusNodes;
  final GlobalKey cardKey;
  final Widget child;

  @override
  State<IngredientCardScrollIntoView> createState() =>
      _IngredientCardScrollIntoViewState();
}

class _IngredientCardScrollIntoViewState extends State<IngredientCardScrollIntoView> {
  void _onAnyFocusNodeChanged() {
    if (!widget.focusNodes.any((n) => n.hasFocus)) return;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      if (!widget.focusNodes.any((n) => n.hasFocus)) return;
      final ctx = widget.cardKey.currentContext;
      if (ctx != null) {
        Scrollable.ensureVisible(
          ctx,
          alignment: 0.08,
          duration: const Duration(milliseconds: 220),
          curve: Curves.easeOutCubic,
        );
      }
    });
  }

  @override
  void initState() {
    super.initState();
    for (final n in widget.focusNodes) {
      n.addListener(_onAnyFocusNodeChanged);
    }
  }

  @override
  void dispose() {
    for (final n in widget.focusNodes) {
      n.removeListener(_onAnyFocusNodeChanged);
    }
    super.dispose();
  }

  @override
  void didUpdateWidget(covariant IngredientCardScrollIntoView oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (listEquals(oldWidget.focusNodes, widget.focusNodes)) return;
    for (final n in oldWidget.focusNodes) {
      n.removeListener(_onAnyFocusNodeChanged);
    }
    for (final n in widget.focusNodes) {
      n.addListener(_onAnyFocusNodeChanged);
    }
  }

  @override
  Widget build(BuildContext context) {
    return KeyedSubtree(
      key: widget.cardKey,
      child: widget.child,
    );
  }
}

// --- Form bodies ---

/// [onMeasurementSystemChanged] is invoked when the user toggles Metric/US (after updating provider).
Widget buildRecipeIngredientEditorBody(
  BuildContext context,
  WidgetRef ref, {
  required RecipeIngredientFormRow row,
  required int index,
  required GlobalKey ingredientCardKey,
  required void Function(void Function() fn) notifyUi,
  required void Function(MeasurementSystem system) onMeasurementSystemChanged,
  VoidCallback? onRemovePressed,
  void Function(int idx, StateSetter? dialogSetState)? onRemoveIngredientAt,
  StateSetter? dialogSetState,
  EdgeInsetsGeometry cardMargin =
      const EdgeInsets.only(bottom: AppSpacing.sm),
}) {
  final scheme = Theme.of(context).colorScheme;
  final qualitativeDropdownValue =
      kRecipeQualitativePresets.contains(row.qualitativePreset)
          ? row.qualitativePreset
          : 'custom';
  final keyboardBottom = MediaQuery.viewInsetsOf(context).bottom;
  final suggestionGridMaxHeight = keyboardBottom > 0 ? 130.0 : 230.0;
  final fieldScrollPadding = EdgeInsets.fromLTRB(
    20,
    20,
    20,
    keyboardBottom + 80,
  );

  return IngredientCardScrollIntoView(
    focusNodes: [
      row.nameFocusNode,
      row.amountFocusNode,
      row.qualitativeCustomFocusNode,
      row.customUnitFocusNode,
    ],
    cardKey: ingredientCardKey,
    child: Container(
      margin: cardMargin,
      padding: const EdgeInsets.fromLTRB(
        AppSpacing.sm,
        AppSpacing.sm,
        AppSpacing.xs,
        AppSpacing.sm,
      ),
      decoration: BoxDecoration(
        color: scheme.surfaceContainerHighest.withValues(alpha: 0.35),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
          color: scheme.primary,
          width: 1.2,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    TextField(
                      controller: row.nameCtrl,
                      focusNode: row.nameFocusNode,
                      textCapitalization: TextCapitalization.sentences,
                      scrollPadding: fieldScrollPadding,
                      onTapOutside: (_) => FocusScope.of(context).unfocus(),
                      style: Theme.of(context).textTheme.bodyLarge,
                      decoration: recipeIngredientInputDecoration(
                        context,
                        hintText: 'Ingredient name',
                        hintStyle:
                            Theme.of(context).textTheme.bodyLarge?.copyWith(
                                  fontStyle: FontStyle.italic,
                                  color: scheme.onSurfaceVariant
                                      .withValues(alpha: 0.5),
                                ),
                        borderOpacity: 0.2,
                        prefixIcon: row.namePickedFromSuggestions &&
                                row.name.isNotEmpty
                            ? Padding(
                                padding: const EdgeInsets.only(left: 8),
                                child: Align(
                                  alignment: Alignment.centerLeft,
                                  widthFactor: 1,
                                  child: ingredientPickedFoodIcon(
                                    context,
                                    ref,
                                    row,
                                  ),
                                ),
                              )
                            : null,
                      ),
                      onChanged: (_) => notifyUi(() {
                        row.namePickedFromSuggestions = false;
                      }),
                    ),
                    if (!row.qualitative)
                      Padding(
                        padding: const EdgeInsets.only(top: 10),
                        child: GroceryItemSuggestionsGrid(
                          repo: ref.read(groceryRepositoryProvider),
                          typedValue: row.nameCtrl.text,
                          recentItems: const [],
                          maxHeight: suggestionGridMaxHeight,
                          onPick: (suggestion) {
                            notifyUi(() {
                              row.nameCtrl.text = suggestion;
                              row.namePickedFromSuggestions = true;
                            });
                            row.nameFocusNode.unfocus();
                          },
                        ),
                      ),
                  ],
                ),
              ),
              IconButton(
                onPressed: () {
                  FocusScope.of(context).unfocus();
                  if (onRemovePressed != null) {
                    onRemovePressed();
                  } else if (onRemoveIngredientAt != null) {
                    onRemoveIngredientAt(index, dialogSetState);
                  }
                },
                icon: const Icon(Icons.delete_outline_rounded),
                tooltip: 'Remove ingredient',
                visualDensity: VisualDensity.compact,
              ),
            ],
          ),
          const SizedBox(height: AppSpacing.sm),
          SegmentedButton<bool>(
            emptySelectionAllowed: false,
            showSelectedIcon: false,
            segments: const [
              ButtonSegment<bool>(
                value: false,
                label: Text('Measure'),
                icon: Icon(Icons.scale_outlined, size: 18),
              ),
              ButtonSegment<bool>(
                value: true,
                label: Text('To taste'),
                icon: Icon(Icons.spa_outlined, size: 18),
              ),
            ],
            selected: {row.qualitative},
            onSelectionChanged: (next) {
              notifyUi(() {
                row.qualitative = next.first;
              });
            },
          ),
          if (row.qualitative) ...[
            const SizedBox(height: AppSpacing.sm),
            DropdownButtonFormField<String>(
              initialValue: qualitativeDropdownValue,
              isExpanded: true,
              decoration: recipeIngredientInputDecoration(
                context,
                labelText: 'Amount',
                contentPadding: const EdgeInsets.symmetric(
                  horizontal: 14,
                  vertical: 12,
                ),
                borderOpacity: 0.2,
              ),
              items: [
                ...kRecipeQualitativePresets.map(
                  (p) => DropdownMenuItem<String>(
                    value: p,
                    child: Text(p),
                  ),
                ),
                const DropdownMenuItem<String>(
                  value: 'custom',
                  child: Text('Custom…'),
                ),
              ],
              onChanged: (value) {
                if (value == null) return;
                notifyUi(() {
                  row.qualitativePreset = value;
                });
              },
            ),
            if (row.qualitativePreset == 'custom') ...[
              const SizedBox(height: AppSpacing.xs),
              TextField(
                controller: row.qualitativeCustomCtrl,
                focusNode: row.qualitativeCustomFocusNode,
                textCapitalization: TextCapitalization.sentences,
                scrollPadding: fieldScrollPadding,
                onTapOutside: (_) => FocusScope.of(context).unfocus(),
                decoration: recipeIngredientInputDecoration(
                  context,
                  hintText: 'e.g. 1½ tsp',
                  borderOpacity: 0.2,
                ),
                onChanged: (_) => notifyUi(() {}),
              ),
            ],
          ] else ...[
            const SizedBox(height: AppSpacing.xs),
            Align(
              alignment: Alignment.centerLeft,
              child: Text(
                'Amount',
                style: Theme.of(context).textTheme.labelMedium?.copyWith(
                      fontWeight: FontWeight.w600,
                      color: scheme.onSurfaceVariant,
                    ),
              ),
            ),
            const SizedBox(height: 4),
            SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: Row(
                children: [
                  for (final preset in kRecipePresetAmountChips)
                    Padding(
                      padding: const EdgeInsets.only(right: 6),
                      child: ChoiceChip(
                        label: Text(
                          preset.label,
                          style: const TextStyle(
                            fontSize: 18,
                            height: 1.1,
                          ),
                        ),
                        labelPadding:
                            const EdgeInsets.symmetric(horizontal: 10),
                        selected: isRecipePresetAmountSelected(
                          row,
                          preset.canonicalText,
                        ),
                        materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                        onSelected: (selected) {
                          notifyUi(() {
                            if (selected) {
                              row.amountCtrl.text = preset.canonicalText;
                            }
                          });
                        },
                      ),
                    ),
                ],
              ),
            ),
            const SizedBox(height: AppSpacing.sm),
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                SizedBox(
                  width: 132,
                  child: TextField(
                    controller: row.amountCtrl,
                    focusNode: row.amountFocusNode,
                    keyboardType: const TextInputType.numberWithOptions(
                      decimal: true,
                    ),
                    scrollPadding: fieldScrollPadding,
                    onTapOutside: (_) => FocusScope.of(context).unfocus(),
                    style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                          fontWeight: FontWeight.w600,
                        ),
                    decoration: recipeIngredientInputDecoration(
                      context,
                      hintText: 'Amount',
                      hintStyle:
                          Theme.of(context).textTheme.bodyLarge?.copyWith(
                                fontStyle: FontStyle.italic,
                                fontWeight: FontWeight.w400,
                                color: scheme.onSurfaceVariant
                                    .withValues(alpha: 0.5),
                              ),
                      contentPadding: const EdgeInsets.symmetric(
                        horizontal: 12,
                        vertical: 12,
                      ),
                      borderOpacity: 0.2,
                    ),
                    onChanged: (_) => notifyUi(() {}),
                  ),
                ),
                const SizedBox(width: AppSpacing.sm),
                Expanded(
                  child: DropdownButtonFormField<String>(
                    key: ValueKey(
                      '${row.reorderId}_${row.unitOptions.join('|')}_${row.selectedUnit}',
                    ),
                    initialValue: row.unitOptions.contains(row.selectedUnit)
                        ? row.selectedUnit
                        : row.unitOptions.first,
                    isDense: true,
                    isExpanded: true,
                    decoration: recipeIngredientInputDecoration(
                      context,
                      labelText: 'Unit',
                      contentPadding: const EdgeInsets.symmetric(
                        horizontal: 14,
                        vertical: 12,
                      ),
                      borderOpacity: 0.2,
                    ),
                    items: row.unitOptions
                        .map(
                          (unit) => DropdownMenuItem(
                            value: unit,
                            child: Text(unit),
                          ),
                        )
                        .toList(),
                    onChanged: (value) {
                      if (value == null) return;
                      notifyUi(() {
                        row.selectedUnit = value;
                      });
                    },
                  ),
                ),
              ],
            ),
            Padding(
              padding: const EdgeInsets.only(
                left: 132 + AppSpacing.sm,
                top: AppSpacing.sm,
              ),
              child: Align(
                alignment: Alignment.centerLeft,
                child: MeasurementSystemToggle(
                  onChanged: onMeasurementSystemChanged,
                ),
              ),
            ),
            if (row.selectedUnit == 'custom') ...[
              const SizedBox(height: AppSpacing.xs),
              TextField(
                controller: row.customUnitCtrl,
                focusNode: row.customUnitFocusNode,
                textCapitalization: TextCapitalization.sentences,
                scrollPadding: fieldScrollPadding,
                onTapOutside: (_) => FocusScope.of(context).unfocus(),
                decoration: recipeIngredientInputDecoration(
                  context,
                  labelText: 'Custom unit',
                  hintText: 'e.g. clove, pinch, can',
                  borderOpacity: 0.2,
                ),
                onChanged: (_) => notifyUi(() {}),
              ),
            ],
          ],
        ],
      ),
    ),
  );
}

Widget buildRecipeDirectionStepBody(
  BuildContext context, {
  required RecipeDirectionDraft draft,
  required int stepIndex,
  required bool showRemoveButton,
  required void Function(void Function() fn) notifyUi,
  VoidCallback? onRemovePressed,
  EdgeInsetsGeometry cardMargin =
      const EdgeInsets.only(bottom: AppSpacing.sm),
}) {
  final scheme = Theme.of(context).colorScheme;

  return Container(
    margin: cardMargin,
    padding: const EdgeInsets.fromLTRB(
      AppSpacing.sm,
      AppSpacing.sm,
      AppSpacing.xs,
      AppSpacing.sm,
    ),
    decoration: BoxDecoration(
      color: kRecipeDirectionStepLight,
      borderRadius: BorderRadius.circular(12),
      border: Border.all(
        color: kRecipeDirectionStepMid,
      ),
    ),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
              decoration: BoxDecoration(
                color: kRecipeDirectionStepMid,
                borderRadius: BorderRadius.circular(20),
              ),
              child: Text(
                'Step ${stepIndex + 1}',
                style: Theme.of(context).textTheme.labelLarge?.copyWith(
                      fontWeight: FontWeight.w700,
                      color: scheme.onSurface,
                    ),
              ),
            ),
            const Spacer(),
            if (showRemoveButton)
              IconButton(
                onPressed: onRemovePressed,
                icon: const Icon(Icons.delete_outline_rounded),
                tooltip: 'Remove step',
                visualDensity: VisualDensity.compact,
              ),
          ],
        ),
        const SizedBox(height: AppSpacing.sm),
        TextField(
          controller: draft.textCtrl,
          maxLines: 4,
          textCapitalization: TextCapitalization.sentences,
          onTapOutside: (_) => FocusScope.of(context).unfocus(),
          decoration: recipeDirectionInstructionDecoration(context),
          onChanged: (_) => notifyUi(() {}),
        ),
      ],
    ),
  );
}

// --- Import outcomes ---

sealed class ImportIngredientEditorOutcome {}

class ImportIngredientEditorSaved extends ImportIngredientEditorOutcome {
  ImportIngredientEditorSaved(this.ingredient);
  final Ingredient ingredient;
}

class ImportIngredientEditorDeleted extends ImportIngredientEditorOutcome {}

sealed class ImportDirectionEditorOutcome {}

class ImportDirectionEditorSaved extends ImportDirectionEditorOutcome {
  ImportDirectionEditorSaved(this.text);
  final String text;
}

class ImportDirectionEditorDeleted extends ImportDirectionEditorOutcome {}

Future<ImportIngredientEditorOutcome?> showImportIngredientEditorDialog(
  BuildContext context,
  WidgetRef ref, {
  Ingredient? initial,
}) async {
  final system = ref.read(measurementSystemProvider);
  final row = hydrateRecipeIngredientFormRow(initial, system);
  final cardKey = GlobalKey();

  final outcome = await showDialog<ImportIngredientEditorOutcome?>(
    context: context,
    useRootNavigator: true,
    barrierDismissible: false,
    builder: (dialogCtx) {
      return StatefulBuilder(
        builder: (context, setModalState) {
          void notifyUi(void Function() fn) {
            fn();
            setModalState(() {});
          }

          final topPad = MediaQuery.paddingOf(dialogCtx).top + 8;
          final maxH = MediaQuery.sizeOf(dialogCtx).height - topPad - 16;
          final width = MediaQuery.sizeOf(dialogCtx).width;

          return Align(
            alignment: Alignment.topCenter,
            child: Padding(
              padding: EdgeInsets.only(top: topPad, left: 12, right: 12),
              child: Material(
                elevation: 8,
                shadowColor: Colors.black45,
                borderRadius: BorderRadius.circular(20),
                clipBehavior: Clip.antiAlias,
                color: Theme.of(dialogCtx).colorScheme.surface,
                child: ConstrainedBox(
                  constraints: BoxConstraints(maxWidth: 560, maxHeight: maxH),
                  child: SizedBox(
                    width: width - 24,
                    child: Theme(
                      data: themeForRecipeEditorModal(dialogCtx),
                      child: Scaffold(
                        resizeToAvoidBottomInset: false,
                        appBar: AppBar(
                          title: Text(
                            initial == null ? 'Add ingredient' : 'Ingredient',
                          ),
                          leading: IconButton(
                            icon: const Icon(Icons.close_rounded),
                            tooltip: 'Cancel',
                            onPressed: () => Navigator.of(dialogCtx).pop(),
                          ),
                        ),
                        body: SingleChildScrollView(
                          padding: EdgeInsets.fromLTRB(
                            16,
                            8,
                            16,
                            16 + MediaQuery.viewInsetsOf(dialogCtx).bottom,
                          ),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.stretch,
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              buildRecipeIngredientEditorBody(
                                dialogCtx,
                                ref,
                                row: row,
                                index: 0,
                                ingredientCardKey: cardKey,
                                notifyUi: notifyUi,
                                onMeasurementSystemChanged: (s) {
                                  applyMeasurementSystemToRow(row, s);
                                  setModalState(() {});
                                },
                                onRemovePressed: () {
                                  FocusScope.of(dialogCtx).unfocus();
                                  Navigator.of(dialogCtx).pop(
                                    ImportIngredientEditorDeleted(),
                                  );
                                },
                                dialogSetState: setModalState,
                              ),
                              const SizedBox(height: 12),
                              Row(
                                children: [
                                  Expanded(
                                    child: OutlinedButton(
                                      onPressed: () =>
                                          Navigator.of(dialogCtx).pop(),
                                      child: const Text('Cancel'),
                                    ),
                                  ),
                                  const SizedBox(width: 12),
                                  Expanded(
                                    child: FilledButton(
                                      onPressed: isRecipeIngredientRowComplete(
                                              row)
                                          ? () {
                                              FocusScope.of(dialogCtx)
                                                  .unfocus();
                                              Navigator.of(dialogCtx).pop(
                                                ImportIngredientEditorSaved(
                                                  ingredientFromFormRow(
                                                    row,
                                                    mergeMetadataFrom: initial,
                                                  ),
                                                ),
                                              );
                                            }
                                          : null,
                                      child: const Text('Save'),
                                    ),
                                  ),
                                ],
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ),
          );
        },
      );
    },
  );

  row.dispose();
  return outcome;
}

Future<ImportDirectionEditorOutcome?> showImportDirectionStepDialog(
  BuildContext context, {
  required int stepIndex,
  required String initialText,
  required bool isNewStep,
  required bool showRemoveButton,
}) async {
  final draft = RecipeDirectionDraft(text: initialText);

  final outcome = await showDialog<ImportDirectionEditorOutcome?>(
    context: context,
    useRootNavigator: true,
    barrierDismissible: false,
    builder: (dialogCtx) {
      return StatefulBuilder(
        builder: (context, setModalState) {
          void notifyUi(void Function() fn) {
            fn();
            setModalState(() {});
          }

          final topPad = MediaQuery.paddingOf(dialogCtx).top + 8;
          final maxH = MediaQuery.sizeOf(dialogCtx).height - topPad - 16;
          final width = MediaQuery.sizeOf(dialogCtx).width;

          return Align(
            alignment: Alignment.topCenter,
            child: Padding(
              padding: EdgeInsets.only(top: topPad, left: 12, right: 12),
              child: Material(
                elevation: 8,
                shadowColor: Colors.black45,
                borderRadius: BorderRadius.circular(20),
                clipBehavior: Clip.antiAlias,
                color: Theme.of(dialogCtx).colorScheme.surface,
                child: ConstrainedBox(
                  constraints: BoxConstraints(maxWidth: 560, maxHeight: maxH),
                  child: SizedBox(
                    width: width - 24,
                    child: Theme(
                      data: themeForRecipeEditorModal(dialogCtx),
                      child: Scaffold(
                        resizeToAvoidBottomInset: false,
                        appBar: AppBar(
                          title: Text(
                            isNewStep
                                ? 'Add step'
                                : 'Step ${stepIndex + 1}',
                          ),
                          leading: IconButton(
                            icon: const Icon(Icons.close_rounded),
                            tooltip: 'Cancel',
                            onPressed: () => Navigator.of(dialogCtx).pop(),
                          ),
                        ),
                        body: SingleChildScrollView(
                          padding: EdgeInsets.fromLTRB(
                            16,
                            8,
                            16,
                            16 + MediaQuery.viewInsetsOf(dialogCtx).bottom,
                          ),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.stretch,
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              buildRecipeDirectionStepBody(
                                dialogCtx,
                                draft: draft,
                                stepIndex: stepIndex,
                                showRemoveButton: showRemoveButton,
                                notifyUi: notifyUi,
                                onRemovePressed: showRemoveButton
                                    ? () {
                                        FocusScope.of(dialogCtx).unfocus();
                                        Navigator.of(dialogCtx).pop(
                                          ImportDirectionEditorDeleted(),
                                        );
                                      }
                                    : null,
                                cardMargin: EdgeInsets.zero,
                              ),
                              const SizedBox(height: 12),
                              Row(
                                children: [
                                  Expanded(
                                    child: OutlinedButton(
                                      onPressed: () =>
                                          Navigator.of(dialogCtx).pop(),
                                      child: const Text('Cancel'),
                                    ),
                                  ),
                                  const SizedBox(width: 12),
                                  Expanded(
                                    child: FilledButton(
                                      onPressed: isRecipeDirectionStepComplete(
                                              draft)
                                          ? () {
                                              FocusScope.of(dialogCtx)
                                                  .unfocus();
                                              Navigator.of(dialogCtx).pop(
                                                ImportDirectionEditorSaved(
                                                  draft.textCtrl.text.trim(),
                                                ),
                                              );
                                            }
                                          : null,
                                      child: const Text('Save'),
                                    ),
                                  ),
                                ],
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ),
          );
        },
      );
    },
  );

  draft.dispose();
  return outcome;
}
