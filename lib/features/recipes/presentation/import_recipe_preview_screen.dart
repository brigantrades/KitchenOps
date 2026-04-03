import 'dart:async';
import 'dart:io';

import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:plateplan/core/models/app_models.dart';
import 'package:plateplan/core/models/instagram_recipe_import.dart';
import 'package:plateplan/core/recipes/recipe_import_reparse_kind.dart';
import 'package:plateplan/core/recipes/recipe_web_import_fetcher.dart';
import 'package:plateplan/core/strings/recipe_title_case.dart';
import 'package:plateplan/core/theme/design_tokens.dart';
import 'package:plateplan/core/ui/section_card.dart';
import 'package:plateplan/features/auth/data/auth_providers.dart';
import 'package:plateplan/features/discover/data/discover_repository.dart';
import 'package:plateplan/features/grocery/data/grocery_repository.dart';
import 'package:plateplan/features/household/data/household_providers.dart';
import 'package:plateplan/features/recipes/data/recipes_repository.dart';
import 'package:plateplan/features/recipes/presentation/recipe_editor_modals.dart';
import 'package:plateplan/features/recipes/presentation/recipe_ingredient_edit_chip.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

enum _ImportRecipePartTab { main, sauce }

/// Passed via [GoRouterState.extra] when opening [ImportRecipePreviewScreen].
class ImportRecipePreviewArgs {
  const ImportRecipePreviewArgs({
    required this.recipe,
    this.sourcePayload,
    this.reparseKind = RecipeImportReparseKind.instagramCaption,
  });

  final Recipe recipe;
  final String? sourcePayload;
  final RecipeImportReparseKind reparseKind;
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
  late TextEditingController _sauceTitleCtrl;
  late List<String> _instructionDrafts;
  late List<String> _sauceInstructionDrafts;
  late bool _servingsEstimated;
  bool _reparseBusy = false;
  bool _saveBusy = false;
  _ImportRecipePartTab _ingredientsPartTab = _ImportRecipePartTab.main;
  _ImportRecipePartTab _instructionsPartTab = _ImportRecipePartTab.main;

  bool _myFavorite = true;
  bool _myToTry = false;
  bool _householdFavorite = false;
  bool _householdToTry = false;

  @override
  void initState() {
    super.initState();
    unawaited(ref.read(groceryRepositoryProvider).ensureCatalogLoaded());
    _recipe = widget.args.recipe;
    _titleCtrl = TextEditingController(
      text: formatRecipeTitlePerWord(_recipe.title),
    );
    _descCtrl = TextEditingController(text: _recipe.description ?? '');
    _instructionDrafts =
        _recipe.instructions.isEmpty ? [''] : _recipe.instructions.toList();
    final emb = _recipe.embeddedSauce;
    _sauceTitleCtrl = TextEditingController(text: emb?.title ?? '');
    _sauceInstructionDrafts = emb == null
        ? <String>[]
        : (emb.instructions.isEmpty
            ? ['']
            : List<String>.from(emb.instructions));
    _servingsEstimated = _isServingsLikelyEstimated(
      servings: _recipe.servings,
      sourcePayload: widget.args.sourcePayload,
    );
  }

  @override
  void dispose() {
    _titleCtrl.dispose();
    _descCtrl.dispose();
    _sauceTitleCtrl.dispose();
    super.dispose();
  }

  Future<void> _reparseWithAi() async {
    final payload = widget.args.sourcePayload;
    if (payload == null || payload.trim().isEmpty) return;
    setState(() => _reparseBusy = true);
    try {
      final gemini = ref.read(geminiServiceProvider);
      Map<String, dynamic>? map;
      if (widget.args.reparseKind == RecipeImportReparseKind.instagramCaption) {
        map = await gemini.extractRecipeFromInstagramContent(payload);
      } else {
        final decoded = decodeWebRecipeImportPayload(payload);
        map = decoded == null
            ? null
            : await gemini.extractRecipeFromWebPageText(
                canonicalUrl: decoded.canonicalUrl,
                pagePlainText: decoded.pageText,
                userNotes: decoded.notes,
              );
        if (map != null &&
            decoded != null &&
            decoded.pageText.trim().isNotEmpty) {
          map = supplementWebImportJsonWithEmbeddedSauceFromPlainText(
            map,
            decoded.pageText,
          );
        }
      }
      if (map == null) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Could not parse recipe. Try again.')),
          );
        }
        return;
      }
      final parsedMap = map;
      final imageUrl = _recipe.imageUrl;
      final shared = widget.args.reparseKind == RecipeImportReparseKind.instagramCaption
          ? payload
          : null;
      setState(() {
        _recipe = recipeFromInstagramGeminiMap(
          parsedMap,
          imageUrl: imageUrl,
          sourceUrl: _recipe.sourceUrl,
          sharedContent: shared,
          source: widget.args.reparseKind == RecipeImportReparseKind.webPage
              ? 'web_import'
              : 'instagram_import',
        );
        _titleCtrl.text = formatRecipeTitlePerWord(_recipe.title);
        _descCtrl.text = _recipe.description ?? '';
        _instructionDrafts =
            _recipe.instructions.isEmpty ? [''] : _recipe.instructions.toList();
        final sauceEmb = _recipe.embeddedSauce;
        if (sauceEmb != null) {
          _sauceTitleCtrl.text = sauceEmb.title ?? '';
          _sauceInstructionDrafts = sauceEmb.instructions.isEmpty
              ? ['']
              : List<String>.from(sauceEmb.instructions);
        } else {
          _sauceTitleCtrl.clear();
          _sauceInstructionDrafts = [];
        }
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
    final sauceInstructions = _sauceInstructionDrafts
        .map((s) => s.trim())
        .where((s) => s.isNotEmpty)
        .toList();
    final emb = _recipe.embeddedSauce;

    var out = _recipe.copyWith(
      title: _titleCtrl.text.trim().isEmpty
          ? _recipe.title
          : formatRecipeTitlePerWord(_titleCtrl.text.trim()),
      description: _descCtrl.text.trim().isEmpty ? null : _descCtrl.text.trim(),
      instructions: instructions,
      ingredients: ingredients,
      isFavorite: favorite,
      isToTry: toTry,
      source: _recipe.source,
      visibility: RecipeVisibility.personal,
    );

    if (emb != null) {
      final sauceTitle = _sauceTitleCtrl.text.trim();
      final sauceIngs =
          emb.ingredients.where((i) => i.name.trim().isNotEmpty).toList();
      if (sauceTitle.isEmpty &&
          sauceIngs.isEmpty &&
          sauceInstructions.isEmpty) {
        out = out.copyWith(clearEmbeddedSauce: true);
      } else {
        out = out.copyWith(
          embeddedSauce: RecipeEmbeddedSauce(
            title: sauceTitle.isEmpty ? null : sauceTitle,
            ingredients: sauceIngs,
            instructions: sauceInstructions,
          ),
        );
      }
    }

    return out;
  }

  void _enableSauceSection() {
    setState(() {
      _recipe = _recipe.copyWith(
        embeddedSauce: const RecipeEmbeddedSauce(),
      );
      _sauceTitleCtrl.clear();
      _sauceInstructionDrafts = [''];
      _ingredientsPartTab = _ImportRecipePartTab.sauce;
      _instructionsPartTab = _ImportRecipePartTab.sauce;
    });
  }

  void _removeSauceSection() {
    setState(() {
      _recipe = _recipe.copyWith(clearEmbeddedSauce: true);
      _sauceTitleCtrl.clear();
      _sauceInstructionDrafts = [];
      _ingredientsPartTab = _ImportRecipePartTab.main;
      _instructionsPartTab = _ImportRecipePartTab.main;
    });
  }

  String get _sauceTabSegmentLabel =>
      _recipe.mealType == MealType.dessert ? 'Frosting' : 'Sauce';

  bool get _hasSauceSection => _recipe.embeddedSauce != null;

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
                    : _recipe.source == 'web_import'
                        ? 'We don’t attach a hero image from website imports. You can add one after saving.'
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
                if (_recipe.source == 'web_import') ...[
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: [
                      const Chip(
                        avatar: Icon(Icons.public_rounded, size: 16),
                        label: Text('Website'),
                      ),
                      if (_recipe.sourceUrl != null &&
                          _recipe.sourceUrl!.trim().isNotEmpty)
                        const Chip(
                          avatar: Icon(Icons.link_rounded, size: 16),
                          label: Text('Source page linked'),
                        ),
                    ],
                  ),
                  const SizedBox(height: AppSpacing.sm),
                ],
                if (_recipe.source == 'book_scan') ...[
                  const Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: [
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
                  textCapitalization: TextCapitalization.words,
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
            subtitle: _hasSauceSection
                ? 'Main is the entrée or primary dish. Use the ${_sauceTabSegmentLabel.toLowerCase()} tab when the recipe lists those ingredients separately (same servings).'
                : 'List ingredients for the main part of the dish. Add a separate section below if the recipe also lists ${_sauceTabSegmentLabel.toLowerCase()} ingredients.',
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                if (_hasSauceSection) ...[
                  SegmentedButton<_ImportRecipePartTab>(
                    segments: [
                      const ButtonSegment<_ImportRecipePartTab>(
                        value: _ImportRecipePartTab.main,
                        label: Text('Main'),
                      ),
                      ButtonSegment<_ImportRecipePartTab>(
                        value: _ImportRecipePartTab.sauce,
                        label: Text(_sauceTabSegmentLabel),
                      ),
                    ],
                    selected: {_ingredientsPartTab},
                    onSelectionChanged: (next) {
                      if (next.isEmpty) return;
                      setState(() => _ingredientsPartTab = next.first);
                    },
                  ),
                  const SizedBox(height: AppSpacing.sm),
                  AnimatedSwitcher(
                    duration: const Duration(milliseconds: 200),
                    child: _ingredientsPartTab == _ImportRecipePartTab.main
                        ? _mainIngredientsColumn(scheme)
                        : _sauceIngredientsOnlyColumn(scheme),
                  ),
                ] else ...[
                  _mainIngredientsColumn(scheme),
                  const SizedBox(height: AppSpacing.sm),
                  Text(
                    'If the page lists a sauce separately (e.g. “Orange sauce”, “For the dressing”), tap Re-parse — the importer tries to split it automatically. You can also add a section by hand.',
                    style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                          color: scheme.onSurfaceVariant,
                          height: 1.35,
                        ),
                  ),
                  const SizedBox(height: AppSpacing.sm),
                  OutlinedButton.icon(
                    onPressed: _enableSauceSection,
                    icon: const Icon(Icons.water_drop_outlined),
                    label: Text(
                      _recipe.mealType == MealType.dessert
                          ? 'Add frosting, icing, or sauce'
                          : 'Add sauce, dressing, or glaze',
                    ),
                  ),
                ],
              ],
            ),
          ),
          const SizedBox(height: AppSpacing.md),
          SectionCard(
            title: 'Instructions',
            subtitle: _hasSauceSection
                ? 'Main is for the primary cooking steps. The ${_sauceTabSegmentLabel.toLowerCase()} tab is only for steps that apply to that part alone.'
                : 'Edit, reorder, and add steps. Add a ${_sauceTabSegmentLabel.toLowerCase()} section under Ingredients if the recipe splits them.',
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                if (_hasSauceSection) ...[
                  SegmentedButton<_ImportRecipePartTab>(
                    segments: [
                      const ButtonSegment<_ImportRecipePartTab>(
                        value: _ImportRecipePartTab.main,
                        label: Text('Main'),
                      ),
                      ButtonSegment<_ImportRecipePartTab>(
                        value: _ImportRecipePartTab.sauce,
                        label: Text(_sauceTabSegmentLabel),
                      ),
                    ],
                    selected: {_instructionsPartTab},
                    onSelectionChanged: (next) {
                      if (next.isEmpty) return;
                      setState(() => _instructionsPartTab = next.first);
                    },
                  ),
                  const SizedBox(height: AppSpacing.sm),
                  AnimatedSwitcher(
                    duration: const Duration(milliseconds: 200),
                    child: _instructionsPartTab == _ImportRecipePartTab.main
                        ? _mainInstructionsColumn(scheme)
                        : _sauceInstructionsColumn(scheme),
                  ),
                ] else
                  _mainInstructionsColumn(scheme),
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

  Widget _mainIngredientsColumn(ColorScheme scheme) {
    return Column(
      key: const ValueKey('imp-ing-main'),
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        for (var i = 0; i < _recipe.ingredients.length; i++)
          Padding(
            padding: const EdgeInsets.only(bottom: AppSpacing.xs),
            child: RecipeIngredientEditChip(
              label: RecipeIngredientEditChip.labelForIngredient(
                _recipe.ingredients[i],
              ),
              style: RecipeIngredientChipStyle.importPink,
              onTap: () async {
                final out = await showImportIngredientEditorDialog(
                  context,
                  ref,
                  initial: _recipe.ingredients[i],
                );
                if (out == null) return;
                if (out is ImportIngredientEditorDeleted) {
                  setState(() {
                    final list = [..._recipe.ingredients]..removeAt(i);
                    _recipe = _recipe.copyWith(ingredients: list);
                  });
                  return;
                }
                if (out is ImportIngredientEditorSaved) {
                  setState(() {
                    final list = [..._recipe.ingredients];
                    list[i] = out.ingredient;
                    _recipe = _recipe.copyWith(ingredients: list);
                  });
                }
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
            final out = await showImportIngredientEditorDialog(context, ref);
            if (out == null || out is ImportIngredientEditorDeleted) {
              return;
            }
            if (out is ImportIngredientEditorSaved) {
              setState(() {
                _recipe = _recipe.copyWith(
                  ingredients: [..._recipe.ingredients, out.ingredient],
                );
              });
            }
          },
          icon: const Icon(Icons.add_rounded),
          label: const Text('Add ingredient'),
        ),
      ],
    );
  }

  Widget _sauceIngredientsOnlyColumn(ColorScheme scheme) {
    return Column(
      key: const ValueKey('imp-ing-sauce'),
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        DecoratedBox(
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(12),
            border: Border.all(
              color: scheme.primary.withValues(alpha: 0.45),
            ),
            color: scheme.primaryContainer.withValues(alpha: 0.22),
          ),
          child: Padding(
            padding: const EdgeInsets.all(12),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Align(
                  alignment: Alignment.centerRight,
                  child: TextButton(
                    onPressed: _removeSauceSection,
                    child: const Text('Remove this section'),
                  ),
                ),
                TextField(
                  controller: _sauceTitleCtrl,
                  decoration: const InputDecoration(
                    labelText: 'Name (optional)',
                    border: OutlineInputBorder(),
                    filled: true,
                  ),
                  textCapitalization: TextCapitalization.words,
                ),
                const SizedBox(height: AppSpacing.sm),
                for (var i = 0;
                    i < _recipe.embeddedSauce!.ingredients.length;
                    i++)
                  Padding(
                    padding: const EdgeInsets.only(bottom: AppSpacing.xs),
                    child: RecipeIngredientEditChip(
                      label: RecipeIngredientEditChip.labelForIngredient(
                        _recipe.embeddedSauce!.ingredients[i],
                      ),
                      style: RecipeIngredientChipStyle.importPink,
                      onTap: () async {
                        final out = await showImportIngredientEditorDialog(
                          context,
                          ref,
                          initial: _recipe.embeddedSauce!.ingredients[i],
                        );
                        if (out == null) return;
                        if (out is ImportIngredientEditorDeleted) {
                          setState(() {
                            final e = _recipe.embeddedSauce!;
                            final list = [...e.ingredients]..removeAt(i);
                            _recipe = _recipe.copyWith(
                              embeddedSauce: RecipeEmbeddedSauce(
                                title: e.title,
                                ingredients: list,
                                instructions: e.instructions,
                              ),
                            );
                          });
                          return;
                        }
                        if (out is ImportIngredientEditorSaved) {
                          setState(() {
                            final e = _recipe.embeddedSauce!;
                            final list = [...e.ingredients];
                            list[i] = out.ingredient;
                            _recipe = _recipe.copyWith(
                              embeddedSauce: RecipeEmbeddedSauce(
                                title: e.title,
                                ingredients: list,
                                instructions: e.instructions,
                              ),
                            );
                          });
                        }
                      },
                      onDelete: () {
                        setState(() {
                          final e = _recipe.embeddedSauce!;
                          final list = [...e.ingredients]..removeAt(i);
                          _recipe = _recipe.copyWith(
                            embeddedSauce: RecipeEmbeddedSauce(
                              title: e.title,
                              ingredients: list,
                              instructions: e.instructions,
                            ),
                          );
                        });
                      },
                    ),
                  ),
                TextButton.icon(
                  onPressed: () async {
                    final out =
                        await showImportIngredientEditorDialog(context, ref);
                    if (out == null || out is ImportIngredientEditorDeleted) {
                      return;
                    }
                    if (out is ImportIngredientEditorSaved) {
                      setState(() {
                        final e = _recipe.embeddedSauce!;
                        _recipe = _recipe.copyWith(
                          embeddedSauce: RecipeEmbeddedSauce(
                            title: e.title,
                            ingredients: [...e.ingredients, out.ingredient],
                            instructions: e.instructions,
                          ),
                        );
                      });
                    }
                  },
                  icon: const Icon(Icons.add_rounded),
                  label: const Text('Add sauce ingredient'),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }

  Widget _mainInstructionsColumn(ColorScheme scheme) {
    return Column(
      key: const ValueKey('imp-dir-main'),
      crossAxisAlignment: CrossAxisAlignment.stretch,
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
                  final out = await showImportDirectionStepDialog(
                    context,
                    stepIndex: index,
                    initialText: step,
                    isNewStep: false,
                    showRemoveButton: _instructionDrafts.length > 1,
                  );
                  if (out == null) return;
                  if (out is ImportDirectionEditorDeleted) {
                    setState(() {
                      if (_instructionDrafts.length <= 1) {
                        _instructionDrafts[0] = '';
                      } else {
                        _instructionDrafts.removeAt(index);
                      }
                    });
                    return;
                  }
                  if (out is ImportDirectionEditorSaved) {
                    setState(() {
                      _instructionDrafts[index] = out.text;
                    });
                  }
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
            final isReplacingEmptyOnly = _instructionDrafts.length == 1 &&
                _instructionDrafts.first.trim().isEmpty;
            final newIndex =
                isReplacingEmptyOnly ? 0 : _instructionDrafts.length;
            final out = await showImportDirectionStepDialog(
              context,
              stepIndex: newIndex,
              initialText: '',
              isNewStep: true,
              showRemoveButton: !isReplacingEmptyOnly,
            );
            if (out == null) return;
            if (out is ImportDirectionEditorDeleted) return;
            if (out is ImportDirectionEditorSaved) {
              setState(() {
                if (isReplacingEmptyOnly) {
                  _instructionDrafts[0] = out.text;
                } else {
                  _instructionDrafts.add(out.text);
                }
              });
            }
          },
          icon: const Icon(Icons.add_rounded),
          label: const Text('Add step'),
        ),
      ],
    );
  }

  Widget _sauceInstructionsColumn(ColorScheme scheme) {
    return Column(
      key: const ValueKey('imp-dir-sauce'),
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        ReorderableListView.builder(
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          buildDefaultDragHandles: false,
          itemCount: _sauceInstructionDrafts.length,
          onReorder: (oldIndex, newIndex) {
            setState(() {
              if (newIndex > oldIndex) newIndex -= 1;
              final item = _sauceInstructionDrafts.removeAt(oldIndex);
              _sauceInstructionDrafts.insert(newIndex, item);
            });
          },
          itemBuilder: (context, index) {
            final step = _sauceInstructionDrafts[index];
            return Padding(
              key: ValueKey('sauce-step-$index-$step'),
              padding: const EdgeInsets.only(bottom: 8),
              child: _InstructionChip(
                index: index,
                text: step,
                onEdit: () async {
                  final out = await showImportDirectionStepDialog(
                    context,
                    stepIndex: index,
                    initialText: step,
                    isNewStep: false,
                    showRemoveButton: _sauceInstructionDrafts.length > 1,
                  );
                  if (out == null) return;
                  if (out is ImportDirectionEditorDeleted) {
                    setState(() {
                      if (_sauceInstructionDrafts.length <= 1) {
                        _sauceInstructionDrafts[0] = '';
                      } else {
                        _sauceInstructionDrafts.removeAt(index);
                      }
                    });
                    return;
                  }
                  if (out is ImportDirectionEditorSaved) {
                    setState(() {
                      _sauceInstructionDrafts[index] = out.text;
                    });
                  }
                },
                onDelete: () {
                  setState(() {
                    if (_sauceInstructionDrafts.length <= 1) {
                      _sauceInstructionDrafts[0] = '';
                      return;
                    }
                    _sauceInstructionDrafts.removeAt(index);
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
            final isReplacingEmptyOnly = _sauceInstructionDrafts.length == 1 &&
                _sauceInstructionDrafts.first.trim().isEmpty;
            final newIndex =
                isReplacingEmptyOnly ? 0 : _sauceInstructionDrafts.length;
            final out = await showImportDirectionStepDialog(
              context,
              stepIndex: newIndex,
              initialText: '',
              isNewStep: true,
              showRemoveButton: !isReplacingEmptyOnly,
            );
            if (out == null) return;
            if (out is ImportDirectionEditorDeleted) return;
            if (out is ImportDirectionEditorSaved) {
              setState(() {
                if (isReplacingEmptyOnly) {
                  _sauceInstructionDrafts[0] = out.text;
                } else {
                  _sauceInstructionDrafts.add(out.text);
                }
              });
            }
          },
          icon: const Icon(Icons.add_rounded),
          label: const Text('Add sauce step'),
        ),
      ],
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
