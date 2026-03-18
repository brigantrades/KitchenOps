import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:plateplan/core/theme/design_tokens.dart';
import 'package:plateplan/core/ui/section_card.dart';

const profileGoalOptions = <String>[
  'build_muscle',
  'lose_weight',
  'more_veg',
  'eat_healthier',
];

const profileDietaryOptions = <String>[
  'vegetarian',
  'vegan',
  'gluten_free',
  'dairy_free',
  'nut_allergy',
];

const profileCuisineOptions = <String>[
  'mediterranean',
  'mexican',
  'italian',
  'indian',
  'asian',
];

const profileDislikedIngredientOptions = <String>[
  'mushroom',
  'onion',
  'cilantro',
  'seafood',
  'spicy_food',
];

const profileServingsOptions = <int>[1, 2, 4, 6];

String profileLabel(String value) {
  return value
      .split('_')
      .map((part) => part.isEmpty ? part : '${part[0].toUpperCase()}${part.substring(1)}')
      .join(' ');
}

class ProfileFormData {
  const ProfileFormData({
    required this.name,
    required this.primaryGoal,
    required this.dietaryRestrictions,
    required this.preferredCuisines,
    required this.dislikedIngredients,
    required this.householdServings,
  });

  final String name;
  final String primaryGoal;
  final List<String> dietaryRestrictions;
  final List<String> preferredCuisines;
  final List<String> dislikedIngredients;
  final int householdServings;
}

class ProfileForm extends StatefulWidget {
  const ProfileForm({
    super.key,
    required this.initialName,
    required this.initialPrimaryGoal,
    required this.initialDietaryRestrictions,
    required this.initialPreferredCuisines,
    required this.initialDislikedIngredients,
    required this.initialHouseholdServings,
    required this.submitLabel,
    required this.onSubmit,
    this.onSkip,
  });

  final String initialName;
  final String initialPrimaryGoal;
  final List<String> initialDietaryRestrictions;
  final List<String> initialPreferredCuisines;
  final List<String> initialDislikedIngredients;
  final int initialHouseholdServings;
  final String submitLabel;
  final Future<void> Function(ProfileFormData data) onSubmit;
  final Future<void> Function()? onSkip;

  @override
  State<ProfileForm> createState() => _ProfileFormState();
}

class _ProfileFormState extends State<ProfileForm> {
  late final TextEditingController _nameCtrl;
  late final TextEditingController _dislikedSearchCtrl;
  late String _primaryGoal;
  late final Set<String> _dietary;
  late final Set<String> _cuisines;
  late final Set<String> _disliked;
  late int _servings;
  List<String> _ingredientCatalog = const [];
  var _saving = false;

  @override
  void initState() {
    super.initState();
    _nameCtrl = TextEditingController(text: widget.initialName);
    _dislikedSearchCtrl = TextEditingController();
    _primaryGoal = widget.initialPrimaryGoal;
    _dietary = widget.initialDietaryRestrictions.toSet();
    _cuisines = widget.initialPreferredCuisines.toSet();
    _disliked = widget.initialDislikedIngredients.toSet();
    _servings = widget.initialHouseholdServings;
    _loadIngredientCatalog();
  }

  @override
  void dispose() {
    _nameCtrl.dispose();
    _dislikedSearchCtrl.dispose();
    super.dispose();
  }

  Future<void> _loadIngredientCatalog() async {
    try {
      final raw = await rootBundle.loadString('assets/data/usda_food_catalog.txt');
      final lines = raw
          .split('\n')
          .map((line) => line.trim())
          .where((line) => line.isNotEmpty)
          .take(7500)
          .toSet();
      if (!mounted) return;
      setState(() {
        _ingredientCatalog = <String>{
          ...profileDislikedIngredientOptions,
          ...lines,
        }.toList();
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _ingredientCatalog = profileDislikedIngredientOptions;
      });
    }
  }

  String _normalizeIngredient(String value) {
    final normalized = value.trim().toLowerCase().replaceAll(RegExp(r'\s+'), ' ');
    return normalized;
  }

  List<String> get _ingredientMatches {
    final query = _normalizeIngredient(_dislikedSearchCtrl.text);
    if (query.isEmpty) return const [];
    final selected = _disliked.map(_normalizeIngredient).toSet();
    final source = _ingredientCatalog.isEmpty ? profileDislikedIngredientOptions : _ingredientCatalog;
    return source
        .where((item) {
          final normalized = _normalizeIngredient(item);
          return normalized.contains(query) && !selected.contains(normalized);
        })
        .take(8)
        .toList();
  }

  void _addDislikedIngredient(String rawValue) {
    final value = _normalizeIngredient(rawValue);
    if (value.isEmpty) return;
    if (_disliked.any((item) => _normalizeIngredient(item) == value)) {
      _dislikedSearchCtrl.clear();
      setState(() {});
      return;
    }
    setState(() {
      _disliked.add(value);
      _dislikedSearchCtrl.clear();
    });
  }

  int get _completionScore {
    var score = 0;
    if (_nameCtrl.text.trim().isNotEmpty) score += 1;
    if (_primaryGoal.trim().isNotEmpty) score += 1;
    if (_dietary.isNotEmpty) score += 1;
    if (_cuisines.isNotEmpty || _disliked.isNotEmpty) score += 1;
    return score;
  }

  String? _validate() {
    if (_nameCtrl.text.trim().isEmpty) {
      return 'Please enter your name.';
    }
    if (_primaryGoal.trim().isEmpty) {
      return 'Please pick one primary goal.';
    }
    return null;
  }

  Future<void> _handleSubmit() async {
    final error = _validate();
    if (error != null) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(error)));
      return;
    }
    setState(() => _saving = true);
    try {
      await widget.onSubmit(
        ProfileFormData(
          name: _nameCtrl.text.trim(),
          primaryGoal: _primaryGoal,
          dietaryRestrictions: _dietary.toList(),
          preferredCuisines: _cuisines.toList(),
          dislikedIngredients: _disliked.toList(),
          householdServings: _servings,
        ),
      );
    } finally {
      if (mounted) {
        setState(() => _saving = false);
      }
    }
  }

  Future<void> _handleSkip() async {
    if (widget.onSkip == null || _saving) return;
    setState(() => _saving = true);
    try {
      await widget.onSkip!();
    } finally {
      if (mounted) {
        setState(() => _saving = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;

    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        Container(
          padding: const EdgeInsets.all(AppSpacing.md),
          decoration: BoxDecoration(
            color: scheme.primaryContainer.withValues(alpha: 0.55),
            borderRadius: AppRadius.md,
          ),
          child: Row(
            children: [
              Icon(Icons.person_outline_rounded, color: scheme.onPrimaryContainer),
              const SizedBox(width: AppSpacing.sm),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Profile setup',
                      style: textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      'Keep this quick. You can edit everything later.',
                      style: textTheme.bodySmall?.copyWith(color: scheme.onSurfaceVariant),
                    ),
                  ],
                ),
              ),
              Chip(
                label: Text('$_completionScore/4'),
                visualDensity: VisualDensity.compact,
              ),
            ],
          ),
        ),
        const SizedBox(height: AppSpacing.md),
        SectionCard(
          title: 'Basics',
          subtitle: 'Required',
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              TextField(
                controller: _nameCtrl,
                onChanged: (_) => setState(() {}),
                textInputAction: TextInputAction.next,
                decoration: const InputDecoration(labelText: 'Your name'),
              ),
              const SizedBox(height: AppSpacing.md),
              Text('Primary goal', style: textTheme.titleSmall),
              const SizedBox(height: AppSpacing.xs),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: profileGoalOptions
                    .map(
                      (goal) => ChoiceChip(
                        label: Text(profileLabel(goal)),
                        selected: _primaryGoal == goal,
                        onSelected: (_) => setState(() => _primaryGoal = goal),
                      ),
                    )
                    .toList(),
              ),
              const SizedBox(height: AppSpacing.md),
              Text('Usually cooking for', style: textTheme.titleSmall),
              const SizedBox(height: AppSpacing.xs),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: profileServingsOptions
                    .map(
                      (servings) => ChoiceChip(
                        label: Text('$servings ${servings == 1 ? 'person' : 'people'}'),
                        selected: _servings == servings,
                        onSelected: (_) => setState(() => _servings = servings),
                      ),
                    )
                    .toList(),
              ),
            ],
          ),
        ),
        const SizedBox(height: AppSpacing.md),
        SectionCard(
          title: 'Dietary needs',
          subtitle: 'Optional but helps recommendations',
          child: Wrap(
            spacing: 8,
            runSpacing: 8,
            children: profileDietaryOptions
                .map(
                  (diet) => FilterChip(
                    label: Text(profileLabel(diet)),
                    selected: _dietary.contains(diet),
                    onSelected: (value) => setState(
                      () => value ? _dietary.add(diet) : _dietary.remove(diet),
                    ),
                  ),
                )
                .toList(),
          ),
        ),
        const SizedBox(height: AppSpacing.md),
        SectionCard(
          title: 'Taste preferences',
          subtitle: 'Optional',
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('Preferred cuisines', style: textTheme.titleSmall),
              const SizedBox(height: AppSpacing.xs),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: profileCuisineOptions
                    .map(
                      (cuisine) => FilterChip(
                        label: Text(profileLabel(cuisine)),
                        selected: _cuisines.contains(cuisine),
                        onSelected: (value) => setState(
                          () => value ? _cuisines.add(cuisine) : _cuisines.remove(cuisine),
                        ),
                      ),
                    )
                    .toList(),
              ),
            ],
          ),
        ),
        const SizedBox(height: AppSpacing.md),
        SectionCard(
          title: 'Ingredients to avoid',
          subtitle: 'Optional',
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              TextField(
                controller: _dislikedSearchCtrl,
                onChanged: (_) => setState(() {}),
                textInputAction: TextInputAction.done,
                onSubmitted: _addDislikedIngredient,
                decoration: const InputDecoration(
                  labelText: 'Search ingredient',
                  hintText: 'e.g., mushroom, cilantro, shrimp',
                  prefixIcon: Icon(Icons.search),
                ),
              ),
              const SizedBox(height: AppSpacing.xs),
              if (_dislikedSearchCtrl.text.trim().isNotEmpty)
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    ..._ingredientMatches.map(
                      (item) => ActionChip(
                        label: Text(profileLabel(item)),
                        onPressed: () => _addDislikedIngredient(item),
                      ),
                    ),
                    ActionChip(
                      label: Text('Add "${_dislikedSearchCtrl.text.trim()}"'),
                      onPressed: () => _addDislikedIngredient(_dislikedSearchCtrl.text),
                    ),
                  ],
                ),
              if (_dislikedSearchCtrl.text.trim().isNotEmpty)
                const SizedBox(height: AppSpacing.sm),
              if (_disliked.isNotEmpty)
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: _disliked
                      .map(
                        (ingredient) => InputChip(
                          label: Text(profileLabel(ingredient)),
                          onDeleted: () => setState(() => _disliked.remove(ingredient)),
                        ),
                      )
                      .toList(),
                ),
            ],
          ),
        ),
        const SizedBox(height: AppSpacing.lg),
        FilledButton.icon(
          onPressed: _saving ? null : _handleSubmit,
          icon: const Icon(Icons.check_circle_outline),
          label: Text(widget.submitLabel),
        ),
        if (widget.onSkip != null) ...[
          const SizedBox(height: AppSpacing.xs),
          TextButton(
            onPressed: _saving ? null : _handleSkip,
            child: const Text('Skip for now'),
          ),
        ],
      ],
    );
  }
}
