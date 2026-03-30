import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:plateplan/core/models/app_models.dart';
import 'package:plateplan/features/household/data/household_providers.dart';
import 'package:plateplan/features/pantry/data/pantry_repository.dart';
import 'package:plateplan/features/pantry/domain/pantry_deficit.dart';
import 'package:plateplan/features/planner/data/planner_repository.dart';
import 'package:plateplan/features/recipes/data/recipes_repository.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

final pantryRepositoryProvider = Provider<PantryRepository>(
  (ref) => PantryRepository(Supabase.instance.client),
);

final pantryItemsProvider = StreamProvider<List<PantryItem>>((ref) async* {
  final hid = ref.watch(activeHouseholdIdProvider);
  if (hid == null || hid.isEmpty) {
    yield const [];
    return;
  }
  final repo = ref.watch(pantryRepositoryProvider);
  yield* repo.streamItems(hid);
});

/// Deficits for the current planner window vs pantry (all week buckets in window).
final pantryDeficitsForPlannerProvider =
    Provider<AsyncValue<PantryDeficitResult>>((ref) {
  final slotsAsync = ref.watch(plannerSlotsProvider);
  final recipesAsync = ref.watch(recipesProvider);
  final pantryAsync = ref.watch(pantryItemsProvider);

  return slotsAsync.when(
    loading: () => const AsyncValue.loading(),
    error: (e, st) => AsyncValue.error(e, st),
    data: (slots) {
      return recipesAsync.when(
        loading: () => const AsyncValue.loading(),
        error: (e, st) => AsyncValue.error(e, st),
        data: (recipes) {
          return pantryAsync.when(
            loading: () => const AsyncValue.loading(),
            error: (e, st) => AsyncValue.error(e, st),
            data: (pantry) {
              final byId = {
                for (final r in recipes) r.id: r,
              };
              final result = PantryDeficitCalculator.compute(
                slots: slots,
                recipeById: byId,
                pantryItems: pantry,
              );
              return AsyncValue.data(result);
            },
          );
        },
      );
    },
  );
});
