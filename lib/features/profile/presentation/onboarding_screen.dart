import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:collection/collection.dart';
import 'package:plateplan/core/models/app_models.dart';
import 'package:plateplan/features/auth/data/auth_providers.dart';
import 'package:plateplan/features/profile/data/profile_providers.dart';
import 'package:plateplan/features/profile/presentation/profile_form.dart';

class OnboardingScreen extends ConsumerWidget {
  const OnboardingScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final user = ref.watch(currentUserProvider);
    if (user == null) {
      return const Scaffold(body: Center(child: Text('Sign in required')));
    }

    final profileRepo = ref.watch(profileRepositoryProvider);
    final profileAsync = ref.watch(profileProvider);

    return Scaffold(
      appBar: AppBar(title: const Text('Welcome')),
      body: profileAsync.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (error, _) => Center(child: Text('Could not load profile: $error')),
        data: (profile) => ProfileForm(
          initialName: profile?.name ?? '',
          initialPrimaryGoal: profile?.goals.firstOrNull ?? 'more_veg',
          initialDietaryRestrictions: profile?.dietaryRestrictions ?? const [],
          initialPreferredCuisines: profile?.preferredCuisines ?? const [],
          initialDislikedIngredients: profile?.dislikedIngredients ?? const [],
          initialHouseholdServings: profile?.householdServings ?? 2,
          submitLabel: 'Continue',
          onSubmit: (form) async {
            final updated = Profile(
              id: user.id,
              name: form.name,
              goals: [form.primaryGoal],
              dietaryRestrictions: form.dietaryRestrictions,
              preferredCuisines: form.preferredCuisines,
              dislikedIngredients: form.dislikedIngredients,
              householdServings: form.householdServings,
              householdId: profile?.householdId,
            );
            await profileRepo.upsertProfile(updated);
            if (!context.mounted) return;
            context.go('/');
          },
          onSkip: () async {
            await profileRepo.upsertProfile(
              Profile(
                id: user.id,
                name: profile?.name.trim().isNotEmpty == true ? profile!.name : 'KitchenOps User',
                goals: profile?.goals.isNotEmpty == true ? profile!.goals : const ['more_veg'],
                dietaryRestrictions: profile?.dietaryRestrictions ?? const [],
                preferredCuisines: profile?.preferredCuisines ?? const [],
                dislikedIngredients: profile?.dislikedIngredients ?? const [],
                householdServings: profile?.householdServings ?? 2,
                householdId: profile?.householdId,
              ),
            );
            if (!context.mounted) return;
            context.go('/');
          },
        ),
      ),
    );
  }
}
