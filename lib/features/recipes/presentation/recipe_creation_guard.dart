import 'package:flutter_riverpod/flutter_riverpod.dart';

class RecipeCreationGuardState {
  const RecipeCreationGuardState({
    this.isOpen = false,
    this.stepIndex = 0,
  });

  final bool isOpen;
  final int stepIndex;

  RecipeCreationGuardState copyWith({
    bool? isOpen,
    int? stepIndex,
  }) {
    return RecipeCreationGuardState(
      isOpen: isOpen ?? this.isOpen,
      stepIndex: stepIndex ?? this.stepIndex,
    );
  }
}

class RecipeCreationGuardNotifier extends StateNotifier<RecipeCreationGuardState> {
  RecipeCreationGuardNotifier() : super(const RecipeCreationGuardState());

  void open() {
    if (state.isOpen) return;
    state = state.copyWith(isOpen: true, stepIndex: 0);
  }

  void setStep(int stepIndex) {
    state = state.copyWith(stepIndex: stepIndex);
  }

  void close() {
    state = const RecipeCreationGuardState();
  }
}

final recipeCreationGuardProvider =
    StateNotifierProvider<RecipeCreationGuardNotifier, RecipeCreationGuardState>(
  (ref) => RecipeCreationGuardNotifier(),
);
