import 'dart:io';

import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:plateplan/core/models/app_models.dart';
import 'package:plateplan/core/models/instagram_recipe_import.dart';
import 'package:plateplan/core/measurement/ingredient_unit_profile.dart';
import 'package:plateplan/core/measurement/measurement_system_provider.dart';
import 'package:plateplan/core/strings/ingredient_amount_display.dart';
import 'package:plateplan/core/theme/design_tokens.dart';
import 'package:plateplan/core/ui/section_card.dart';
import 'package:plateplan/features/auth/data/auth_providers.dart';
import 'package:plateplan/features/discover/data/discover_repository.dart';
import 'package:plateplan/features/household/data/household_providers.dart';
import 'package:plateplan/features/recipes/data/recipes_repository.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

/// Matches recipe editor qualitative presets ([recipes_screen]).
const _kImportQualitativePresets = [
  'to taste',
  'as needed',
  'pinch',
  '1 tsp',
  '1 tbsp',
  '½ tsp',
];

/// Passed via [GoRouterState.extra] when opening [ImportRecipePreviewScreen].
class ImportRecipePreviewArgs {
  const ImportRecipePreviewArgs({
    required this.recipe,
    this.sourcePayload,
  });

  final Recipe recipe;
  final String? sourcePayload;
}

class ImportRecipePreviewScreen extends ConsumerStatefulWidget {
  const ImportRecipePreviewScreen({
    super.key,
    required this.args,
  });

  final ImportRecipePreviewArgs args;

  @override
  ConsumerState<ImportRecipePreviewScreen> createState() =>
      _ImportRecipePreviewScreenState();
}

class _ImportRecipePreviewScreenState
    extends ConsumerState<ImportRecipePreviewScreen> {
  late Recipe _recipe;
  late TextEditingController _titleCtrl;
  late TextEditingController _descCtrl;
  late List<String> _instructionDrafts;
  late bool _servingsEstimated;
  bool _reparseBusy = false;
  bool _saveBusy = false;

  bool _myFavorite = true;
  bool _myToTry = false;
  bool _householdFavorite = false;
  bool _householdToTry = false;

  @override
  void initState() {
    super.initState();
    _recipe = widget.args.recipe;
    _titleCtrl = TextEditingController(text: _recipe.title);
    _descCtrl = TextEditingController(text: _recipe.description ?? '');
    _instructionDrafts =
        _recipe.instructions.isEmpty ? [''] : _recipe.instructions.toList();
    _servingsEstimated = _isServingsLikelyEstimated(
      servings: _recipe.servings,
      sourcePayload: widget.args.sourcePayload,
    );
  }

  @override
  void dispose() {
    _titleCtrl.dispose();
    _descCtrl.dispose();
    super.dispose();
  }

  Future<void> _reparseWithAi() async {
    final payload = widget.args.sourcePayload;
    if (payload == null || payload.trim().isEmpty) return;
    setState(() => _reparseBusy = true);
    try {
      final map = await ref
          .read(geminiServiceProvider)
          .extractRecipeFromInstagramContent(payload);
      if (map == null) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Could not parse recipe. Try again.')),
          );
        }
        return;
      }
      final imageUrl = _recipe.imageUrl;
      setState(() {
        _recipe = recipeFromInstagramGeminiMap(
          map,
          imageUrl: imageUrl,
          sourceUrl: _recipe.sourceUrl,
          sharedContent: payload,
        );
        _titleCtrl.text = _recipe.title;
        _descCtrl.text = _recipe.description ?? '';
        _instructionDrafts =
            _recipe.instructions.isEmpty ? [''] : _recipe.instructions.toList();
        _servingsEstimated = _isServingsLikelyEstimated(
          servings: _recipe.servings,
          sourcePayload: payload,
        );
      });
    } finally {
      if (mounted) setState(() => _reparseBusy = false);
    }
  }

  Recipe _buildRecipeFromForm({required bool favorite, required bool toTry}) {
    final instructions = _instructionDrafts
        .map((s) => s.trim())
        .where((s) => s.isNotEmpty)
        .toList();
    final ingredients = _recipe.ingredients
        .where((i) => i.name.trim().isNotEmpty)
        .toList();
    return _recipe.copyWith(
      title: _titleCtrl.text.trim().isEmpty
          ? _recipe.title
          : _titleCtrl.text.trim(),
      description: _descCtrl.text.trim().isEmpty ? null : _descCtrl.text.trim(),
      instructions: instructions,
      ingredients: ingredients,
      isFavorite: favorite,
      isToTry: toTry,
      source: _recipe.source,
      visibility: RecipeVisibility.personal,
    );
  }

  Future<void> _save() async {
    final user = ref.read(currentUserProvider);
    if (user == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Sign in required.')),
      );
      return;
    }
    final hasShared =
        ref.read(hasSharedHouseholdProvider).valueOrNull ?? false;
    final anyHouseholdList = hasShared &&
        (_householdFavorite || _householdToTry);
    if (!_myFavorite &&
        !_myToTry &&
        !anyHouseholdList) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'Turn on at least one option — My Recipes and/or Household.',
          ),
        ),
      );
      return;
    }
    setState(() => _saveBusy = true);
    try {
      final draft = _buildRecipeFromForm(
        favorite: _myFavorite,
        toTry: _myToTry,
      );
      final repo = ref.read(recipesRepositoryProvider);
      final id = await repo.create(
        user.id,
        draft,
        shareWithHousehold: false,
        visibilityOverride: RecipeVisibility.personal,
      );
      if (anyHouseholdList) {
        await repo.copyPersonalRecipeToHousehold(
          userId: user.id,
          recipeId: id,
          householdFavorite: _householdFavorite,
          householdToTry: _householdToTry,
        );
      }
      ref.invalidate(recipesProvider);
      if (!mounted) return;
      final msg = anyHouseholdList
          ? 'Saved to My Recipes and Household Recipes.'
          : 'Recipe imported successfully!';
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(msg)),
      );
      context.go('/cooking/$id');
    } on PostgrestException catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Could not save: ${e.message}')),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Could not save: $e')),
        );
      }
    } finally {
      if (mounted) setState(() => _saveBusy = false);
    }
  }

  String _saveSelectionSummary(bool hasSharedHousehold) {
    final bits = <String>[];
    if (_myFavorite) bits.add('My Favorites');
    if (_myToTry) bits.add('My To Try');
    if (hasSharedHousehold && _householdFavorite) {
      bits.add('Household Favorites');
    }
    if (hasSharedHousehold && _householdToTry) bits.add('Household To Try');
    if (bits.isEmpty) return 'Tap to choose lists';
    return bits.join(' · ');
  }

  Future<void> _openSaveToSheet() async {
    if (_saveBusy) return;
    final hasShared =
        ref.read(hasSharedHouseholdProvider).valueOrNull ?? false;
    final scheme = Theme.of(context).colorScheme;
    await showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      isScrollControlled: true,
      useSafeArea: true,
      builder: (sheetContext) {
        return StatefulBuilder(
          builder: (context, setModalState) {
            void updateToggle(VoidCallback fn) {
              setState(fn);
              setModalState(() {});
            }

            return Padding(
              padding: EdgeInsets.only(
                bottom: MediaQuery.viewInsetsOf(sheetContext).bottom,
              ),
              child: SingleChildScrollView(
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(20, 0, 20, 24),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Text(
                        'Save to lists',
                        style: Theme.of(context).textTheme.titleMedium?.copyWith(
                              fontWeight: FontWeight.w800,
                            ),
                      ),
                      const SizedBox(height: 6),
                      Text(
                        'Turn on any combination.',
                        style: Theme.of(context).textTheme.bodySmall?.copyWith(
                              color: scheme.onSurfaceVariant,
                            ),
                      ),
                      const SizedBox(height: 16),
                      Text(
                        'My Recipes',
                        style: Theme.of(context).textTheme.labelLarge?.copyWith(
                              color: scheme.onSurfaceVariant,
                              fontWeight: FontWeight.w600,
                            ),
                      ),
                      SwitchListTile.adaptive(
                        contentPadding: EdgeInsets.zero,
                        secondary: Icon(
                          _myFavorite
                              ? Icons.favorite_rounded
                              : Icons.favorite_border_rounded,
                          color: _myFavorite
                              ? scheme.primary
                              : scheme.onSurfaceVariant,
                        ),
                        title: const Text('Favorites'),
                        subtitle: const Text('Your personal Favorites list'),
                        value: _myFavorite,
                        onChanged: (v) => updateToggle(() => _myFavorite = v),
                      ),
                      SwitchListTile.adaptive(
                        contentPadding: EdgeInsets.zero,
                        secondary: Icon(
                          _myToTry
                              ? Icons.flag_rounded
                              : Icons.outlined_flag_rounded,
                          color: _myToTry
                              ? scheme.primary
                              : scheme.onSurfaceVariant,
                        ),
                        title: const Text('To Try'),
                        subtitle: const Text('Your personal To Try list'),
                        value: _myToTry,
                        onChanged: (v) => updateToggle(() => _myToTry = v),
                      ),
                      if (hasShared) ...[
                        const SizedBox(height: 8),
                        Text(
                          'Household Recipes',
                          style:
                              Theme.of(context).textTheme.labelLarge?.copyWith(
                                    color: scheme.onSurfaceVariant,
                                    fontWeight: FontWeight.w600,
                                  ),
                        ),
                        Padding(
                          padding: const EdgeInsets.only(bottom: 4, top: 4),
                          child: Text(
                            'Adds a shared copy when either option is on.',
                            style: Theme.of(context)
                                .textTheme
                                .bodySmall
                                ?.copyWith(color: scheme.onSurfaceVariant),
                          ),
                        ),
                        SwitchListTile.adaptive(
                          contentPadding: EdgeInsets.zero,
                          secondary: Icon(
                            _householdFavorite
                                ? Icons.favorite_rounded
                                : Icons.favorite_border_rounded,
                            color: _householdFavorite
                                ? scheme.primary
                                : scheme.onSurfaceVariant,
                          ),
                          title: const Text('Favorites'),
                          subtitle: const Text('Household Favorites list'),
                          value: _householdFavorite,
                          onChanged: (v) =>
                              updateToggle(() => _householdFavorite = v),
                        ),
                        SwitchListTile.adaptive(
                          contentPadding: EdgeInsets.zero,
                          secondary: Icon(
                            _householdToTry
                                ? Icons.flag_rounded
                                : Icons.outlined_flag_rounded,
                            color: _householdToTry
                                ? scheme.primary
                                : scheme.onSurfaceVariant,
                          ),
                          title: const Text('To Try'),
                          subtitle: const Text('Household To Try list'),
                          value: _householdToTry,
                          onChanged: (v) =>
                              updateToggle(() => _householdToTry = v),
                        ),
                      ],
                      const SizedBox(height: 16),
                      FilledButton(
                        onPressed: () {
                          Navigator.of(sheetContext).pop();
                          _save();
                        },
                        child: const Text('Save recipe'),
                      ),
                    ],
                  ),
                ),
              ),
            );
          },
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final imageUrl = _recipe.imageUrl;
    final hasSharedHousehold =
        ref.watch(hasSharedHouseholdProvider).valueOrNull ?? false;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Import recipe'),
        leading: IconButton(
          icon: const Icon(Icons.close_rounded),
          onPressed: _saveBusy ? null : () => context.pop(),
        ),
        actions: [
          if (widget.args.sourcePayload != null &&
              widget.args.sourcePayload!.trim().isNotEmpty)
            TextButton(
              onPressed: _reparseBusy || _saveBusy ? null : _reparseWithAi,
              child: _reparseBusy
                  ? const SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Text('Re-parse'),
            ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
        children: [
          if (imageUrl != null && imageUrl.isNotEmpty) ...[
            ClipRRect(
              borderRadius: AppRadius.md,
              child: AspectRatio(
                aspectRatio: 16 / 10,
                child: _buildHeroImage(imageUrl, scheme),
              ),
            ),
            const SizedBox(height: AppSpacing.md),
          ] else ...[
            Padding(
              padding: const EdgeInsets.only(bottom: AppSpacing.xs),
              child: _placeholderImage(scheme),
            ),
            Padding(
              padding: const EdgeInsets.only(bottom: AppSpacing.md, left: 4),
              child: Text(
                _recipe.source == 'book_scan'
                    ? 'No photo was attached. Try scanning again with better light and a steady shot.'
                    : 'Image appears only when Instagram includes media in the share payload.',
                style: Theme.of(context)
                    .textTheme
                    .bodySmall
                    ?.copyWith(color: scheme.onSurfaceVariant),
              ),
            ),
          ],
          SectionCard(
            title: 'Basics',
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                if (_recipe.source == 'instagram_import') ...[
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: [
                      const Chip(
                        avatar: Icon(Icons.camera_alt_rounded, size: 16),
                        label: Text('Instagram'),
                      ),
                      if (_recipe.sourceUrl != null &&
                          _recipe.sourceUrl!.trim().isNotEmpty)
                        const Chip(
                          avatar: Icon(Icons.link_rounded, size: 16),
                          label: Text('Original post linked'),
                        ),
                    ],
                  ),
                  const SizedBox(height: AppSpacing.sm),
                ],
                if (_recipe.source == 'book_scan') ...[
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: const [
                      Chip(
                        avatar: Icon(Icons.menu_book_rounded, size: 16),
                        label: Text('Cookbook scan'),
                      ),
                    ],
                  ),
                  const SizedBox(height: AppSpacing.sm),
                ],
                TextField(
                  controller: _titleCtrl,
                  textCapitalization: TextCapitalization.sentences,
                  decoration: const InputDecoration(
                    labelText: 'Title',
                    border: OutlineInputBorder(),
                  ),
                ),
                const SizedBox(height: AppSpacing.sm),
                TextField(
                  controller: _descCtrl,
                  maxLines: 3,
                  textCapitalization: TextCapitalization.sentences,
                  decoration: const InputDecoration(
                    labelText: 'Description',
                    border: OutlineInputBorder(),
                  ),
                ),
                const SizedBox(height: AppSpacing.sm),
                InputDecorator(
                  decoration: const InputDecoration(
                    labelText: 'Meal type',
                    border: OutlineInputBorder(),
                  ),
                  child: DropdownButtonHideUnderline(
                    child: DropdownButton<MealType>(
                      isExpanded: true,
                      value: _recipe.mealType,
                      items: MealType.values
                          .map(
                            (m) => DropdownMenuItem(
                              value: m,
                              child: Text(_mealLabel(m)),
                            ),
                          )
                          .toList(),
                      onChanged: (v) {
                        if (v == null) return;
                        setState(() => _recipe = _recipe.copyWith(mealType: v));
                      },
                    ),
                  ),
                ),
                const SizedBox(height: AppSpacing.sm),
                _ServingsEstimateField(
                  servings: _recipe.servings,
                  isEstimated: _servingsEstimated,
                  onSet: (value) => setState(() {
                    _recipe = _recipe.copyWith(servings: value);
                    _servingsEstimated = false;
                  }),
                ),
              ],
            ),
          ),
          const SizedBox(height: AppSpacing.md),
          SectionCard(
            title: 'Cuisine tags',
            child: Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                ..._recipe.cuisineTags.map(
                  (t) => Chip(
                    label: Text(t),
                    onDeleted: () {
                      setState(() {
                        _recipe = _recipe.copyWith(
                          cuisineTags: _recipe.cuisineTags
                              .where((x) => x != t)
                              .toList(),
                        );
                      });
                    },
                  ),
                ),
                ActionChip(
                  label: const Text('+ Add'),
                  onPressed: () async {
                    final next = await _promptTag(context);
                    if (next == null || next.isEmpty) return;
                    setState(() {
                      _recipe = _recipe.copyWith(
                        cuisineTags: [..._recipe.cuisineTags, next],
                      );
                    });
                  },
                ),
              ],
            ),
          ),
          const SizedBox(height: AppSpacing.md),
          SectionCard(
            title: 'Ingredients',
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                for (var i = 0; i < _recipe.ingredients.length; i++)
                  Padding(
                    padding: const EdgeInsets.only(bottom: AppSpacing.xs),
                    child: _IngredientChip(
                      ingredient: _recipe.ingredients[i],
                      onTap: () async {
                        final edited = await _promptIngredient(
                          context,
                          initial: _recipe.ingredients[i],
                        );
                        if (edited == null) return;
                        setState(() {
                          final list = [..._recipe.ingredients];
                          list[i] = edited;
                          _recipe = _recipe.copyWith(ingredients: list);
                        });
                      },
                      onDelete: () {
                        setState(() {
                          final list = [..._recipe.ingredients]..removeAt(i);
                          _recipe = _recipe.copyWith(ingredients: list);
                        });
                      },
                    ),
                  ),
                TextButton.icon(
                  onPressed: () async {
                    final created = await _promptIngredient(context);
                    if (created == null) return;
                    setState(() {
                      _recipe = _recipe.copyWith(
                        ingredients: [..._recipe.ingredients, created],
                      );
                    });
                  },
                  icon: const Icon(Icons.add_rounded),
                  label: const Text('Add ingredient'),
                ),
              ],
            ),
          ),
          const SizedBox(height: AppSpacing.md),
          SectionCard(
            title: 'Instructions',
            child: Column(
              children: [
                ReorderableListView.builder(
                  shrinkWrap: true,
                  physics: const NeverScrollableScrollPhysics(),
                  buildDefaultDragHandles: false,
                  itemCount: _instructionDrafts.length,
                  onReorder: (oldIndex, newIndex) {
                    setState(() {
                      if (newIndex > oldIndex) newIndex -= 1;
                      final item = _instructionDrafts.removeAt(oldIndex);
                      _instructionDrafts.insert(newIndex, item);
                    });
                  },
                  itemBuilder: (context, index) {
                    final step = _instructionDrafts[index];
                    return Padding(
                      key: ValueKey('step-$index-$step'),
                      padding: const EdgeInsets.only(bottom: 8),
                      child: _InstructionChip(
                        index: index,
                        text: step,
                        onEdit: () async {
                          final edited = await _promptInstruction(
                            context,
                            initial: step,
                            index: index,
                          );
                          if (edited == null) return;
                          setState(() {
                            _instructionDrafts[index] = edited;
                          });
                        },
                        onDelete: () {
                          setState(() {
                            if (_instructionDrafts.length <= 1) {
                              _instructionDrafts[0] = '';
                              return;
                            }
                            _instructionDrafts.removeAt(index);
                          });
                        },
                        dragHandle: ReorderableDragStartListener(
                          index: index,
                          child: Padding(
                            padding: const EdgeInsets.only(right: 6),
                            child: Icon(
                              Icons.drag_handle_rounded,
                              color: scheme.onSurfaceVariant,
                            ),
                          ),
                        ),
                      ),
                    );
                  },
                ),
                TextButton.icon(
                  onPressed: () async {
                    final created = await _promptInstruction(
                      context,
                      initial: '',
                      index: _instructionDrafts.length,
                    );
                    if (created == null) return;
                    setState(() {
                      if (_instructionDrafts.length == 1 &&
                          _instructionDrafts.first.trim().isEmpty) {
                        _instructionDrafts[0] = created;
                      } else {
                        _instructionDrafts.add(created);
                      }
                    });
                  },
                  icon: const Icon(Icons.add_rounded),
                  label: const Text('Add step'),
                ),
              ],
            ),
          ),
        ],
      ),
      bottomNavigationBar: SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 6, 16, 10),
          child: _saveBusy
              ? const SizedBox(
                  height: 52,
                  child: Center(
                    child: SizedBox(
                      width: 24,
                      height: 24,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    ),
                  ),
                )
              : Material(
                  color: scheme.surfaceContainerLow,
                  borderRadius: BorderRadius.circular(16),
                  clipBehavior: Clip.antiAlias,
                  child: InkWell(
                    onTap: _openSaveToSheet,
                    child: Padding(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 16,
                        vertical: 12,
                      ),
                      child: Row(
                        children: [
                          Icon(
                            Icons.bookmark_add_outlined,
                            color: scheme.primary,
                            size: 24,
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Text(
                                  'Save to',
                                  style: Theme.of(context)
                                      .textTheme
                                      .titleSmall
                                      ?.copyWith(fontWeight: FontWeight.w800),
                                ),
                                const SizedBox(height: 2),
                                Text(
                                  _saveSelectionSummary(hasSharedHousehold),
                                  style: Theme.of(context)
                                      .textTheme
                                      .bodySmall
                                      ?.copyWith(
                                        color: scheme.onSurfaceVariant,
                                      ),
                                  maxLines: 2,
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ],
                            ),
                          ),
                          Icon(
                            Icons.keyboard_arrow_up_rounded,
                            color: scheme.onSurfaceVariant,
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
        ),
      ),
    );
  }

  Widget _buildHeroImage(String imageUrl, ColorScheme scheme) {
    if (imageUrl.startsWith('http')) {
      return CachedNetworkImage(
        imageUrl: imageUrl,
        fit: BoxFit.cover,
        errorWidget: (_, __, ___) => _placeholderImage(scheme),
      );
    }
    final f = File(imageUrl);
    if (f.existsSync()) {
      return Image.file(
        f,
        fit: BoxFit.cover,
        errorBuilder: (_, __, ___) => _placeholderImage(scheme),
      );
    }
    return _placeholderImage(scheme);
  }

  Widget _placeholderImage(ColorScheme scheme) {
    return Container(
      height: 160,
      decoration: BoxDecoration(
        color: scheme.surfaceContainerHighest,
        borderRadius: AppRadius.md,
      ),
      alignment: Alignment.center,
      child: Icon(
        Icons.image_outlined,
        size: 48,
        color: scheme.outline,
      ),
    );
  }

  String _mealLabel(MealType m) => switch (m) {
        MealType.entree => 'Entree',
        MealType.side => 'Side',
        MealType.sauce => 'Sauce',
        MealType.snack => 'Snack',
        MealType.dessert => 'Dessert',
      };

  Future<String?> _promptTag(BuildContext context) async {
    final ctrl = TextEditingController();
    final result = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Add tag'),
        content: TextField(
          controller: ctrl,
          decoration: const InputDecoration(hintText: 'e.g. Italian'),
          autofocus: true,
          textCapitalization: TextCapitalization.words,
          onSubmitted: (v) => Navigator.pop(ctx, v.trim()),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, ctrl.text.trim()),
            child: const Text('Add'),
          ),
        ],
      ),
    );
    ctrl.dispose();
    return result;
  }

  Future<Ingredient?> _promptIngredient(
    BuildContext context, {
    Ingredient? initial,
  }) async {
    final system = ref.read(measurementSystemProvider);
    final nameCtrl = TextEditingController(text: initial?.name ?? '');
    final amountCtrl = TextEditingController(
      text: initial == null
          ? ''
          : initial.qualitative
              ? ''
              : formatIngredientAmount(initial.amount),
    );
    final customUnitCtrl = TextEditingController();
    final qualitativeCustomCtrl = TextEditingController();

    var profile = detectUnitProfile(nameCtrl.text.trim(), system);
    var unitOptions = List<String>.from(profile.options);
    var selectedUnit = profile.defaultUnit;
    var qualitativePreset = 'to taste';

    var qualitative = initial?.qualitative ?? false;
    if (initial != null) {
      if (initial.qualitative) {
        final t = initial.unit.trim();
        if (t.isEmpty) {
          qualitativePreset = 'to taste';
        } else if (_kImportQualitativePresets.contains(t)) {
          qualitativePreset = t;
        } else {
          qualitativePreset = 'custom';
          qualitativeCustomCtrl.text = t;
        }
      } else {
        profile = detectUnitProfile(initial.name, system);
        unitOptions = List<String>.from(profile.options);
        final nu = initial.unit.trim().toLowerCase();
        final isCustom =
            !profile.options.any((o) => o.toLowerCase() == nu);
        if (isCustom) {
          selectedUnit = 'custom';
          customUnitCtrl.text = initial.unit;
        } else {
          selectedUnit =
              matchUnitOption(profile.options, initial.unit) ??
                  profile.defaultUnit;
        }
      }
    }

    final result = await showDialog<Ingredient>(
      context: context,
      builder: (ctx) {
        return StatefulBuilder(builder: (ctx, setLocal) {
          void onNameChanged() {
            setLocal(() {
              profile = detectUnitProfile(nameCtrl.text.trim(), system);
              unitOptions = List<String>.from(profile.options);
              if (selectedUnit != 'custom' &&
                  !unitOptions.contains(selectedUnit)) {
                selectedUnit = profile.defaultUnit;
              }
            });
          }

          return AlertDialog(
            title: Text(initial == null ? 'Add ingredient' : 'Edit ingredient'),
            content: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  TextField(
                    controller: nameCtrl,
                    decoration: const InputDecoration(
                      labelText: 'Ingredient',
                      border: OutlineInputBorder(),
                    ),
                    onChanged: (_) => onNameChanged(),
                  ),
                  const SizedBox(height: AppSpacing.sm),
                  SwitchListTile.adaptive(
                    contentPadding: EdgeInsets.zero,
                    value: qualitative,
                    onChanged: (v) => setLocal(() {
                      qualitative = v;
                      if (!v) {
                        profile =
                            detectUnitProfile(nameCtrl.text.trim(), system);
                        unitOptions = List<String>.from(profile.options);
                        selectedUnit = profile.defaultUnit;
                        customUnitCtrl.clear();
                      }
                    }),
                    title: const Text('Free-text amount'),
                    subtitle: const Text('Use for “to taste”, “pinch”, etc.'),
                  ),
                  const SizedBox(height: AppSpacing.xs),
                  if (qualitative) ...[
                    DropdownButtonFormField<String>(
                      key: ValueKey<String>(qualitativePreset),
                      initialValue: qualitativePreset,
                      isExpanded: true,
                      decoration: const InputDecoration(
                        labelText: 'Amount',
                        border: OutlineInputBorder(),
                      ),
                      items: [
                        ..._kImportQualitativePresets.map(
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
                        setLocal(() => qualitativePreset = value);
                      },
                    ),
                    if (qualitativePreset == 'custom') ...[
                      const SizedBox(height: AppSpacing.sm),
                      TextField(
                        controller: qualitativeCustomCtrl,
                        decoration: const InputDecoration(
                          labelText: 'Custom amount text',
                          border: OutlineInputBorder(),
                        ),
                        textCapitalization: TextCapitalization.sentences,
                      ),
                    ],
                  ] else ...[
                    TextField(
                      controller: amountCtrl,
                      keyboardType: const TextInputType.numberWithOptions(
                        decimal: true,
                      ),
                      decoration: const InputDecoration(
                        labelText: 'Amount',
                        border: OutlineInputBorder(),
                      ),
                    ),
                    const SizedBox(height: AppSpacing.sm),
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Expanded(
                          child: DropdownButtonFormField<String>(
                            key: ValueKey(
                              '${unitOptions.join('|')}_$selectedUnit',
                            ),
                            initialValue: unitOptions.contains(selectedUnit)
                                ? selectedUnit
                                : unitOptions.last,
                            isExpanded: true,
                            decoration: const InputDecoration(
                              labelText: 'Unit',
                              border: OutlineInputBorder(),
                            ),
                            items: unitOptions
                                .map(
                                  (u) => DropdownMenuItem<String>(
                                    value: u,
                                    child: Text(u),
                                  ),
                                )
                                .toList(),
                            onChanged: (value) {
                              if (value == null) return;
                              setLocal(() {
                                selectedUnit = value;
                                if (value != 'custom') {
                                  customUnitCtrl.clear();
                                }
                              });
                            },
                          ),
                        ),
                      ],
                    ),
                    if (selectedUnit == 'custom') ...[
                      const SizedBox(height: AppSpacing.sm),
                      TextField(
                        controller: customUnitCtrl,
                        decoration: const InputDecoration(
                          labelText: 'Custom unit',
                          border: OutlineInputBorder(),
                        ),
                      ),
                    ],
                  ],
                ],
              ),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(ctx),
                child: const Text('Cancel'),
              ),
              FilledButton(
                onPressed: () {
                  final name = nameCtrl.text.trim();
                  if (name.isEmpty) return;
                  if (qualitative) {
                    String qUnit;
                    if (qualitativePreset == 'custom') {
                      qUnit = qualitativeCustomCtrl.text.trim();
                    } else {
                      qUnit = qualitativePreset;
                    }
                    Navigator.pop(
                      ctx,
                      Ingredient(
                        name: name,
                        amount: 0,
                        unit: qUnit,
                        category: GroceryCategory.other,
                        qualitative: true,
                      ),
                    );
                    return;
                  }
                  final amount =
                      _tryParseAmountText(amountCtrl.text.trim()) ?? 0;
                  final unit = selectedUnit == 'custom'
                      ? customUnitCtrl.text.trim()
                      : selectedUnit;
                  if (unit.isEmpty) return;
                  Navigator.pop(
                    ctx,
                    Ingredient(
                      name: name,
                      amount: amount,
                      unit: unit,
                      category: GroceryCategory.other,
                      qualitative: false,
                    ),
                  );
                },
                child: const Text('Save'),
              ),
            ],
          );
        });
      },
    );
    nameCtrl.dispose();
    amountCtrl.dispose();
    customUnitCtrl.dispose();
    qualitativeCustomCtrl.dispose();
    return result;
  }

  Future<String?> _promptInstruction(
    BuildContext context, {
    required String initial,
    required int index,
  }) async {
    final ctrl = TextEditingController(text: initial);
    final result = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('Step ${index + 1}'),
        content: TextField(
          controller: ctrl,
          minLines: 3,
          maxLines: 10,
          decoration: const InputDecoration(
            hintText: 'Describe this step...',
            border: OutlineInputBorder(),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, ctrl.text.trim()),
            child: const Text('Save'),
          ),
        ],
      ),
    );
    ctrl.dispose();
    return result;
  }

  double? _tryParseAmountText(String raw) {
    final text = raw.trim();
    if (text.isEmpty) return null;
    return double.tryParse(text.replaceAll(',', '.'));
  }

  bool _isServingsLikelyEstimated({
    required int servings,
    required String? sourcePayload,
  }) {
    // Heuristic: if shared text doesn't mention yield/servings and we landed on
    // the default common value, mark as estimated.
    final text = (sourcePayload ?? '').toLowerCase();
    final mentionsServings = RegExp(
      r'\b(serves?|servings?|yield|makes?)\b',
      caseSensitive: false,
    ).hasMatch(text);
    return !mentionsServings && servings == 2;
  }
}

class _IngredientChip extends StatelessWidget {
  const _IngredientChip({
    required this.ingredient,
    required this.onTap,
    required this.onDelete,
  });

  final Ingredient ingredient;
  final VoidCallback onTap;
  final VoidCallback onDelete;

  String _summary() {
    final name = ingredient.name.trim().isEmpty ? 'Ingredient' : ingredient.name;
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

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;
    return Material(
      color: Colors.transparent,
      child: InkWell(
        borderRadius: BorderRadius.circular(999),
        onTap: onTap,
        child: Ink(
          decoration: BoxDecoration(
            color: const Color(0xFFFFE8EE),
            borderRadius: BorderRadius.circular(999),
            border: Border.all(color: const Color(0xFFE8A8B8)),
          ),
          child: Padding(
            padding: const EdgeInsets.only(left: 10, right: 4, top: 8, bottom: 8),
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
                    _summary(),
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
                  constraints: const BoxConstraints(minWidth: 36, minHeight: 36),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _InstructionChip extends StatelessWidget {
  const _InstructionChip({
    required this.index,
    required this.text,
    required this.onEdit,
    required this.onDelete,
    required this.dragHandle,
  });

  final int index;
  final String text;
  final VoidCallback onEdit;
  final VoidCallback onDelete;
  final Widget dragHandle;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final label = text.trim().isEmpty ? 'Tap to add this step' : text.trim();
    return Material(
      color: Colors.transparent,
      child: InkWell(
        borderRadius: AppRadius.sm,
        onTap: onEdit,
        child: Ink(
          decoration: BoxDecoration(
            color: scheme.surface,
            borderRadius: AppRadius.sm,
            border: Border.all(color: scheme.outlineVariant),
          ),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 10),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                dragHandle,
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Step ${index + 1}',
                        style: Theme.of(context).textTheme.labelSmall?.copyWith(
                              color: scheme.onSurfaceVariant,
                            ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        label,
                        maxLines: 3,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: AppSpacing.xs),
                Icon(Icons.edit_outlined, size: 18, color: scheme.onSurfaceVariant),
                IconButton(
                  onPressed: onDelete,
                  icon: const Icon(Icons.close_rounded, size: 20),
                  visualDensity: VisualDensity.compact,
                  padding: EdgeInsets.zero,
                  constraints: const BoxConstraints(minWidth: 36, minHeight: 36),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _ServingsEstimateField extends StatelessWidget {
  const _ServingsEstimateField({
    required this.servings,
    required this.isEstimated,
    required this.onSet,
  });

  final int servings;
  final bool isEstimated;
  final void Function(int value) onSet;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Text(
              'Servings (AI estimate)',
              style: Theme.of(context).textTheme.labelLarge,
            ),
            const SizedBox(width: 6),
            Icon(Icons.auto_awesome_rounded, size: 16, color: scheme.primary),
            if (isEstimated) ...[
              const SizedBox(width: 8),
              Chip(
                label: const Text('Estimated'),
                visualDensity: VisualDensity.compact,
                materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                backgroundColor: scheme.primary.withValues(alpha: 0.12),
                side: BorderSide(color: scheme.primary.withValues(alpha: 0.35)),
              ),
            ],
          ],
        ),
        const SizedBox(height: AppSpacing.xs),
        Wrap(
          spacing: 6,
          runSpacing: 6,
          children: [
            for (final preset in const [2, 3, 4, 6, 8])
              ChoiceChip(
                label: Text('$preset'),
                selected: servings == preset,
                onSelected: (_) => onSet(preset),
              ),
            ActionChip(
              label: Text(servings > 8 ? '$servings' : 'Custom'),
              onPressed: () async {
                final ctrl = TextEditingController(text: servings.toString());
                final next = await showDialog<int>(
                  context: context,
                  builder: (ctx) => AlertDialog(
                    title: const Text('Set servings'),
                    content: TextField(
                      controller: ctrl,
                      keyboardType: TextInputType.number,
                      decoration: const InputDecoration(
                        border: OutlineInputBorder(),
                        labelText: 'Servings',
                      ),
                    ),
                    actions: [
                      TextButton(
                        onPressed: () => Navigator.pop(ctx),
                        child: const Text('Cancel'),
                      ),
                      FilledButton(
                        onPressed: () {
                          final value = int.tryParse(ctrl.text.trim());
                          if (value == null || value < 1 || value > 99) return;
                          Navigator.pop(ctx, value);
                        },
                        child: const Text('Save'),
                      ),
                    ],
                  ),
                );
                ctrl.dispose();
                if (next != null) onSet(next);
              },
            ),
          ],
        ),
      ],
    );
  }
}
