import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_tts/flutter_tts.dart';
import 'package:collection/collection.dart';
import 'package:plateplan/features/recipes/data/recipes_repository.dart';

class CookingModeScreen extends ConsumerStatefulWidget {
  const CookingModeScreen({super.key, required this.recipeId});

  final String recipeId;

  @override
  ConsumerState<CookingModeScreen> createState() => _CookingModeScreenState();
}

class _CookingModeScreenState extends ConsumerState<CookingModeScreen> {
  final FlutterTts _tts = FlutterTts();
  int _stepIndex = 0;
  final Set<int> _checkedIngredients = {};

  @override
  Widget build(BuildContext context) {
    final recipesAsync = ref.watch(recipesProvider);
    final scheme = Theme.of(context).colorScheme;

    return Scaffold(
      appBar: AppBar(title: const Text('Cooking')),
      body: recipesAsync.when(
        data: (recipes) {
          final recipe =
              recipes.firstWhereOrNull((r) => r.id == widget.recipeId);
          if (recipe == null) {
            return const Center(child: Text('Recipe not found'));
          }

          final steps = recipe.instructions.isEmpty
              ? const ['Follow your recipe details.']
              : recipe.instructions;
          final step = steps[_stepIndex.clamp(0, steps.length - 1)];

          return ListView(
            padding: const EdgeInsets.all(16),
            children: [
              Text(recipe.title,
                  style: Theme.of(context).textTheme.headlineMedium),
              const SizedBox(height: 10),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  Chip(label: Text('${recipe.ingredients.length} ingredients')),
                  Chip(label: Text('${steps.length} steps')),
                  Chip(
                    label: const Text('Cook mode'),
                    backgroundColor: scheme.secondary,
                    labelStyle: TextStyle(color: scheme.onSecondary),
                  ),
                ],
              ),
              const SizedBox(height: 16),
              Text('Ingredients',
                  style: Theme.of(context).textTheme.titleLarge),
              const SizedBox(height: 6),
              ...recipe.ingredients.asMap().entries.map(
                    (entry) => Card(
                      margin: const EdgeInsets.only(bottom: 8),
                      child: CheckboxListTile(
                        value: _checkedIngredients.contains(entry.key),
                        title: Text(
                            '${entry.value.amount} ${entry.value.unit} ${entry.value.name}'),
                        onChanged: (_) {
                          setState(() {
                            if (_checkedIngredients.contains(entry.key)) {
                              _checkedIngredients.remove(entry.key);
                            } else {
                              _checkedIngredients.add(entry.key);
                            }
                          });
                        },
                      ),
                    ),
                  ),
              const Divider(),
              Text('Step ${_stepIndex + 1}/${steps.length}',
                  style: Theme.of(context).textTheme.titleMedium),
              const SizedBox(height: 8),
              Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: scheme.surfaceContainerHighest,
                  borderRadius: BorderRadius.circular(24),
                ),
                child: Text(step, style: Theme.of(context).textTheme.bodyLarge),
              ),
              const SizedBox(height: 16),
              Row(
                children: [
                  Expanded(
                    child: ElevatedButton(
                      onPressed: _stepIndex == 0
                          ? null
                          : () => setState(() => _stepIndex--),
                      child: const Text('Previous'),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: FilledButton(
                      onPressed: _stepIndex >= steps.length - 1
                          ? null
                          : () => setState(() => _stepIndex++),
                      child: const Text('Next Step'),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              Wrap(
                spacing: 8,
                children: [
                  FilledButton.tonal(
                    onPressed: () => _tts.speak(step),
                    child: const Text('Voice'),
                  ),
                  FilledButton.tonal(
                    onPressed: () async {
                      await showTimePicker(
                        context: context,
                        initialTime: TimeOfDay.now(),
                      );
                    },
                    child: const Text('Timer'),
                  ),
                ],
              ),
            ],
          );
        },
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (error, _) => Center(child: Text('Error: $error')),
      ),
    );
  }
}
